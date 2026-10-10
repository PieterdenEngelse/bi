use anyhow::Result;

use super::{Action, ActionInfo, ActionKind, ActionProvider, RunCommand, Urgency};
use crate::collector::Subject;
use crate::system;

/// A staged system addition that has not been installed into /etc/nixos.
///
/// The app writes only as you. Getting a file into `/etc` is a separate,
/// privileged act, and keeping it separate is what makes it visible: the
/// polkit prompt happens here, for a copy, rather than silently inside the
/// thing that rendered the file.
///
/// Offered only when the staged rendering and the installed one actually
/// differ, so it disappears the moment they agree.
pub struct StagedSystemConfig;

/// `install` rather than `cp`: it sets the mode in the same step, so the file
/// cannot briefly exist with whatever umask the service happened to have.
const INSTALL: &str = "install";

impl ActionProvider for StagedSystemConfig {
    fn id(&self) -> &'static str {
        "system-config"
    }

    fn actions(&self) -> Result<Vec<Action>> {
        let Some(staged) = system::staged_path() else {
            return Ok(Vec::new());
        };
        // Nothing staged means the app has never been asked to change system
        // configuration, which is the normal state.
        let Ok(staged_text) = std::fs::read_to_string(&staged) else {
            return Ok(Vec::new());
        };

        let installed_path = system::installed_path();
        // Readable by anyone; only the write needs root. Absent is a
        // legitimate state - it means the file has never been installed.
        let installed_text = std::fs::read_to_string(&installed_path).unwrap_or_default();

        if staged_text == installed_text {
            return Ok(Vec::new());
        }

        let staged_keys = system::read_enabled(&staged_text);
        let installed_keys = system::read_enabled(&installed_text);
        let summary = if staged_keys.is_empty() {
            "removing every system addition".to_string()
        } else {
            format!("adding {}", staged_keys.join(", "))
        };

        Ok(vec![Action {
            id: "install-system-config".into(),
            title: "Install the prepared system configuration".into(),
            subject: Subject::NixOS,
            kind: ActionKind::Shell,
            why: format!(
                "A system configuration file is prepared but not installed: \
                 {summary}.\n\
                 staged:    {} ({})\n\
                 installed: {} ({})",
                staged.display(),
                if staged_keys.is_empty() {
                    "empty".into()
                } else {
                    staged_keys.join(", ")
                },
                installed_path.display(),
                if installed_keys.is_empty() {
                    "empty or absent".into()
                } else {
                    installed_keys.join(", ")
                },
            ),
            info: ActionInfo {
                what: "Copies the prepared file into /etc/nixos, where your \
                       configuration.nix imports it. That needs root, so \
                       polkit will ask you to authenticate - and the prompt \
                       is what permits it. The file itself only adds packages \
                       and environment variables; it touches nothing that \
                       affects whether the machine boots.",
                if_wrong: "Installing changes nothing on its own - the system \
                           is rebuilt from /etc/nixos, not watched. A rebuild \
                           action will appear once this lands. If you want to \
                           undo it, switch the toggle off and install again: \
                           the file is rewritten whole, so an empty one \
                           removes everything it added.",
            },
            command: format!(
                "# review it first:\n\
                 diff {} {}\n\
                 # then install:\n\
                 sudo install -m 0644 {} {}",
                installed_path.display(),
                staged.display(),
                staged.display(),
                installed_path.display(),
            ),
            // Only the install. The displayed text leads with a diff, which
            // must not be conflated with it - and `sudo` there is for reading,
            // since this runs through pkexec instead.
            run: Some(RunCommand {
                program: INSTALL.into(),
                args: vec![
                    "-m".into(),
                    "0644".into(),
                    staged.display().to_string(),
                    installed_path.display().to_string(),
                ],
                elevate: true,
                cwd: None,
            }),
            effects: vec![
                format!("Writes {}", installed_path.display()),
                "Adds packages and environment variables only".into(),
                "Nothing takes effect until the next nixos-rebuild".into(),
            ],
            needs_root: true,
            urgency: Urgency::Advised,
        }])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_run_spec_installs_and_does_not_diff() {
        // The displayed command leads with a diff for you to read. Running
        // that too would be harmless but pointless; running only the install
        // is the point of keeping the two apart.
        for action in StagedSystemConfig.actions().unwrap() {
            let run = action.run.as_ref().expect("must be runnable");
            assert_eq!(run.program, INSTALL);
            assert!(!run.args.iter().any(|a| a == "diff"));
            assert!(run.elevate, "writing /etc needs the prompt");
        }
    }

    #[test]
    fn the_target_is_the_generated_file_never_configuration_nix() {
        // The one thing that must never happen: the app writing over
        // hand-written system configuration.
        for action in StagedSystemConfig.actions().unwrap() {
            let run = action.run.as_ref().unwrap();
            let target = run.args.last().unwrap();
            assert!(
                target.ends_with("nixdash-system.nix"),
                "install target is {target:?}"
            );
            assert!(!target.ends_with("configuration.nix"));
            assert!(!target.ends_with("hardware-configuration.nix"));
        }
    }
}
