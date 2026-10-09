use std::{process::Command, time::Duration};

use serde::Serialize;

use super::RunCommand;

/// How long a single action may run before it is given up on.
///
/// `nixos-rebuild switch` can legitimately take many minutes, so this is
/// generous. It exists to stop a wedged command holding a worker forever, not
/// to bound honest work.
const TIMEOUT: Duration = Duration::from_secs(1800);

#[derive(Debug, Clone, Serialize)]
pub struct RunOutcome {
    /// The exact argv that was executed, so what happened is inspectable
    /// afterwards rather than inferred from the display text.
    pub argv: Vec<String>,
    pub elevated: bool,
    pub exit_code: Option<i32>,
    pub stdout: String,
    pub stderr: String,
    /// Set when the engine could not even start the command.
    pub error: Option<String>,
}

impl RunOutcome {
    pub fn succeeded(&self) -> bool {
        self.error.is_none() && self.exit_code == Some(0)
    }
}

/// Where NixOS keeps setuid binaries. MUST be searched before the system
/// profile.
///
/// This is a NixOS-specific trap that costs an afternoon if you miss it.
/// `/run/current-system/sw/bin/pkexec` exists and is mode `r-xr-xr-x` - not
/// setuid. The setuid copy is a separate wrapper in `/run/wrappers/bin`. Run
/// the one in the system profile and pkexec refuses immediately, complaining
/// that it is not setuid root, which reads like a broken polkit install rather
/// than the wrong path to the right program.
const WRAPPER_BIN: &str = "/run/wrappers/bin";

/// Where NixOS puts the system profile's binaries.
const SYSTEM_BIN: &str = "/run/current-system/sw/bin";

/// Resolve a program name to an absolute path when we can.
///
/// This matters specifically under pkexec. pkexec deliberately discards the
/// caller's environment and hands the program a sanitised
/// `PATH=/usr/sbin:/usr/bin:/sbin:/bin` - which on NixOS is very nearly empty.
/// A bare `systemctl` would resolve from *our* PATH at spawn time, but
/// anything the program then shells out to would not. Naming the absolute path
/// is both more precise about what is being run and the only form that
/// survives the environment being stripped.
fn resolve_program(program: &str) -> String {
    if program.starts_with('/') {
        return program.to_string();
    }
    for dir in [WRAPPER_BIN, SYSTEM_BIN] {
        let candidate = format!("{dir}/{program}");
        if std::path::Path::new(&candidate).exists() {
            return candidate;
        }
    }
    // Leave it bare and let exec report ENOENT, which `run` turns into a
    // readable "could not start" rather than a silent failure.
    program.to_string()
}

/// Build the argv actually handed to the OS.
///
/// Elevation goes through `pkexec`, never `sudo`: sudo wants a terminal and a
/// password on stdin, which a background service does not have, and would
/// either hang or silently fail. pkexec raises a desktop prompt that you
/// answer - which is the point. `--disable-internal-agent` makes it fail
/// cleanly when no polkit agent is running, instead of blocking forever on a
/// prompt nobody can see.
fn argv_for(cmd: &RunCommand) -> Vec<String> {
    let mut argv = Vec::new();
    if cmd.elevate {
        argv.push(resolve_program("pkexec"));
        argv.push("--disable-internal-agent".to_string());
    }
    argv.push(resolve_program(&cmd.program));
    argv.extend(cmd.args.iter().cloned());
    argv
}

/// Execute one action.
///
/// Note what this does NOT do: no shell. The program and arguments are passed
/// to exec directly, so nothing in them is word-split, glob-expanded or
/// interpreted. An action's arguments come from system state (a unit name, for
/// instance), and routing those through `sh -c` would turn a strangely named
/// unit into command injection.
pub fn run(cmd: &RunCommand) -> RunOutcome {
    let argv = argv_for(cmd);
    let mut outcome = RunOutcome {
        argv: argv.clone(),
        elevated: cmd.elevate,
        exit_code: None,
        stdout: String::new(),
        stderr: String::new(),
        error: None,
    };

    tracing::info!(argv = ?argv, elevated = cmd.elevate, "running action");

    let mut child = match Command::new(&argv[0])
        .args(&argv[1..])
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => {
            outcome.error = Some(format!("could not start {}: {e}", argv[0]));
            return outcome;
        }
    };

    // Drain both pipes on their own threads. This is not tidiness: a pipe
    // holds about 64K, and `nixos-rebuild switch` emits far more than that.
    // Polling try_wait() without reading would block the child on a full pipe
    // while we waited for it to exit - a deadlock that only ends at the
    // timeout, and looks exactly like a slow rebuild.
    let out_pipe = child.stdout.take().map(drain);
    let err_pipe = child.stderr.take().map(drain);

    // wait_timeout would need another dependency; polling is adequate for a
    // handful of long-running commands and keeps the dependency list honest.
    let deadline = std::time::Instant::now() + TIMEOUT;
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break Some(status),
            Ok(None) => {
                if std::time::Instant::now() > deadline {
                    let _ = child.kill();
                    let _ = child.wait();
                    outcome.error = Some(format!(
                        "timed out after {} minutes",
                        TIMEOUT.as_secs() / 60
                    ));
                    break None;
                }
                std::thread::sleep(Duration::from_millis(200));
            }
            Err(e) => {
                outcome.error = Some(format!("waiting for {}: {e}", argv[0]));
                break None;
            }
        }
    };

    // The readers end when the child closes its pipes, which has happened by
    // the time it is reaped or killed, so these joins do not add waiting.
    outcome.stdout = out_pipe.map(collect).unwrap_or_default();
    outcome.stderr = err_pipe.map(collect).unwrap_or_default();
    outcome.exit_code = status.and_then(|s| s.code());

    // pkexec's own failure modes are indistinguishable from the command's
    // without this: 126 is "not authorised or dismissed", 127 is "could not
    // run at all". Both would otherwise be reported as the action failing.
    if cmd.elevate && outcome.error.is_none() {
        match outcome.exit_code {
            Some(126) => {
                outcome.error = Some(
                    "not authorised - the polkit prompt was dismissed, or no \
                     agent is running to show it"
                        .into(),
                )
            }
            Some(127) => outcome.error = Some("pkexec could not run the command".into()),
            _ => {}
        }
    }

    outcome
}

fn drain<R: std::io::Read + Send + 'static>(mut r: R) -> std::thread::JoinHandle<String> {
    std::thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = r.read_to_end(&mut buf);
        String::from_utf8_lossy(&buf).trim_end().to_string()
    })
}

fn collect(h: std::thread::JoinHandle<String>) -> String {
    h.join().unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cmd(program: &str, args: &[&str], elevate: bool) -> RunCommand {
        RunCommand {
            program: program.into(),
            args: args.iter().map(|s| s.to_string()).collect(),
            elevate,
        }
    }

    #[test]
    fn elevated_commands_go_through_pkexec_not_sudo() {
        let argv = argv_for(&cmd("systemctl", &["restart", "x"], true));
        assert!(argv[0].ends_with("pkexec"), "{argv:?}");
        assert!(argv.contains(&"--disable-internal-agent".to_string()));
        // sudo would need a tty and a password on stdin; a background service
        // has neither, so it must never appear.
        assert!(!argv.iter().any(|a| a.ends_with("sudo")), "{argv:?}");
    }

    #[test]
    fn unelevated_commands_exec_directly_with_arguments_intact() {
        let argv = argv_for(&cmd("systemctl", &["--user", "restart", "x"], false));
        assert!(argv[0].ends_with("systemctl"), "{argv:?}");
        assert_eq!(&argv[1..], ["--user", "restart", "x"]);
    }

    #[test]
    fn absolute_paths_are_left_alone() {
        assert_eq!(resolve_program("/bin/sh"), "/bin/sh");
    }

    /// Guards the trap documented on WRAPPER_BIN: the system-profile pkexec is
    /// not setuid, so resolving to it means pkexec can never escalate.
    #[test]
    fn pkexec_resolves_to_the_setuid_wrapper() {
        let wrapper = format!("{WRAPPER_BIN}/pkexec");
        if !std::path::Path::new(&wrapper).exists() {
            eprintln!("no {wrapper} on this machine - skipping");
            return;
        }
        assert_eq!(resolve_program("pkexec"), wrapper);
    }

    #[test]
    fn unresolvable_programs_stay_bare_for_exec_to_reject() {
        assert_eq!(
            resolve_program("nixdash-definitely-not-installed"),
            "nixdash-definitely-not-installed"
        );
    }

    #[test]
    fn arguments_are_not_shell_interpreted() {
        // A unit name is system-supplied. If argv went through a shell this
        // would run `touch`; passed to exec it is just a strange argument.
        let out = run(&cmd("echo", &["; touch /tmp/nixdash-injection-canary"], false));
        assert!(out.succeeded(), "{out:?}");
        assert!(out.stdout.contains("touch"), "argument should be literal");
        assert!(
            !std::path::Path::new("/tmp/nixdash-injection-canary").exists(),
            "argument was executed by a shell"
        );
    }

    #[test]
    fn reports_a_missing_program_rather_than_panicking() {
        let out = run(&cmd("nixdash-no-such-program", &[], false));
        assert!(!out.succeeded());
        assert!(out.error.unwrap().contains("could not start"));
    }

    #[test]
    fn captures_exit_code_and_streams() {
        let out = run(&cmd("sh", &["-c", "echo out; echo err >&2; exit 3"], false));
        assert_eq!(out.exit_code, Some(3));
        assert_eq!(out.stdout, "out");
        assert_eq!(out.stderr, "err");
        assert!(!out.succeeded());
    }
}
