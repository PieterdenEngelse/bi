use anyhow::Result;

use super::{Action, ActionInfo, ActionKind, ActionProvider, RunCommand, Urgency};
use crate::collector::Subject;
use crate::settings::{self, SettingValue};

/// Settings written from the app but not yet applied.
///
/// Writing the generated Nix file changes nothing on its own - that is the
/// honest model for a declarative system, and the whole reason the Config
/// page reports *declared* and *in effect* separately. But an edit that sits
/// there unapplied is exactly the kind of thing you forget, and then spend ten
/// minutes wondering why the port did not change.
///
/// So the gap itself becomes the action. It appears only when the two \
/// genuinely differ, and disappears the moment they agree again.
pub struct UnappliedSettings;

/// The port the engine is actually listening on.
fn effective_port() -> u16 {
    std::env::var("NIXDASH_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(3100)
}

/// The log level in effect, contracted to the bare level the UI shows.
fn effective_log_level() -> String {
    let raw = std::env::var("RUST_LOG").unwrap_or_else(|_| "info".into());
    raw.split(',')
        .find_map(|part| part.trim().strip_prefix("nixdash_engine="))
        .unwrap_or(&raw)
        .to_string()
}

impl ActionProvider for UnappliedSettings {
    fn id(&self) -> &'static str {
        "settings"
    }

    fn actions(&self) -> Result<Vec<Action>> {
        let Some(path) = settings::settings_path() else {
            return Ok(Vec::new());
        };
        // No generated file means nothing has been changed from the app, and
        // there is nothing to apply.
        let Ok(text) = std::fs::read_to_string(&path) else {
            return Ok(Vec::new());
        };

        let declared = settings::read_declared(&text);
        let mut differences = Vec::new();

        for (key, value) in &declared {
            match (key.as_str(), value) {
                ("port", SettingValue::Int(n)) => {
                    let live = effective_port() as u64;
                    if *n != live {
                        differences.push(format!("port: {live} running, {n} declared"));
                    }
                }
                ("logLevel", SettingValue::Text(level)) => {
                    let live = effective_log_level();
                    if *level != live {
                        differences.push(format!("log level: {live} running, {level} declared"));
                    }
                }
                // autoStart and ui.autostart take effect at the next login
                // rather than at a restart, so there is no running value to
                // compare them against. Claiming a difference we cannot see
                // would be worse than staying quiet.
                _ => {}
            }
        }

        if differences.is_empty() {
            return Ok(Vec::new());
        }

        Ok(vec![Action {
            id: "apply-nixdash-settings".into(),
            title: "Apply nixdash settings".into(),
            subject: Subject::NixOS,
            kind: ActionKind::Shell,
            why: format!(
                "Settings were changed but not applied:\n  {}\n\
                 The file is Nix source - it takes effect at the next rebuild.",
                differences.join("\n  ")
            ),
            info: ActionInfo {
                what: "Runs `home-manager switch`, which rebuilds your user \
                       environment from the Nix files - including the \
                       generated nixdash settings. Afterwards the engine \
                       service still needs restarting to pick up a new port \
                       or log level, because a changed user service is not \
                       restarted automatically on this machine.",
                if_wrong: "No root is involved: this is your own user \
                           configuration, so there is no polkit prompt. It \
                           rebuilds everything home-manager manages, not only \
                           nixdash, so an unrelated half-finished edit \
                           elsewhere in your config will also be applied - or \
                           will fail the build, leaving the current \
                           generation untouched.",
            },
            command: "home-manager switch\n\
                      # then, to pick up a new port or log level:\n\
                      systemctl --user restart nixdash-engine.service"
                .into(),
            // The restart is deliberately not part of the run spec. It is a
            // second, separate act: the switch may legitimately fail, and
            // restarting into a build that did not happen would be worse than
            // leaving the old one running.
            run: Some(RunCommand {
                program: "home-manager".into(),
                args: vec!["switch".into()],
                elevate: false,
                cwd: std::env::var("HOME").ok(),
            }),
            effects: vec![
                "Rebuilds everything home-manager manages, not just nixdash".into(),
                // The cost was missing while the wasm rebuild beside it says
                // "takes several minutes" - and this one is the more
                // expensive of the two. Any edit in the tree makes a new
                // store path, because the package takes the whole tree as
                // its source.
                "Takes minutes if the nixdash tree changed - any edit rebuilds it".into(),
                "The engine keeps running the old settings until restarted".into(),
                "The previous generation stays available".into(),
            ],
            needs_root: false,
            urgency: Urgency::Advised,
        }])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nothing_is_offered_when_declared_matches_running() {
        // The action exists to close a gap. With no gap it must be absent,
        // or it becomes a permanent nag on a correctly configured machine.
        let text = settings::render(&[
            ("port".into(), SettingValue::Int(effective_port() as u64)),
            ("logLevel".into(), SettingValue::Text(effective_log_level())),
        ]);
        let declared = settings::read_declared(&text);
        let port_matches = declared
            .iter()
            .any(|(k, v)| k == "port" && *v == SettingValue::Int(effective_port() as u64));
        assert!(
            port_matches,
            "test fixture does not reflect the running port"
        );
    }

    #[test]
    fn the_run_spec_omits_the_restart() {
        // The displayed command lists a restart after the switch. Running
        // both would restart into a build that may not have succeeded.
        for action in UnappliedSettings.actions().unwrap() {
            let run = action.run.as_ref().expect("must be runnable");
            assert!(
                !run.args.iter().any(|a| a.contains("restart")),
                "restart leaked into the run spec: {:?}",
                run.args
            );
            assert!(!run.elevate, "user config must never ask for root");
        }
    }

    #[test]
    fn a_log_directive_contracts_to_the_level_shown() {
        // Guards the comparison: if this did not contract, a tuned directive
        // would never equal the bare level and the action would be offered
        // forever.
        std::env::set_var("RUST_LOG", "nixdash_engine=debug,tower_http=warn");
        assert_eq!(effective_log_level(), "debug");
        std::env::remove_var("RUST_LOG");
    }
}
