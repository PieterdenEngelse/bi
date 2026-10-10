use anyhow::Result;

use super::{Action, ActionInfo, ActionKind, ActionProvider, RunCommand, Urgency};
use crate::collector::Subject;

/// NixOS switches `/run/current-system` on every `nixos-rebuild switch`, but
/// `/run/booted-system` only changes on boot. When they differ, the running
/// kernel/initrd is not the one the current generation specifies - easy to
/// accumulate over weeks of rebuilds and completely invisible otherwise.
pub struct RebootNeeded;

impl ActionProvider for RebootNeeded {
    fn id(&self) -> &'static str {
        "reboot"
    }

    fn actions(&self) -> Result<Vec<Action>> {
        let booted = std::fs::read_link("/run/booted-system").ok();
        let current = std::fs::read_link("/run/current-system").ok();

        let (Some(booted), Some(current)) = (booted, current) else {
            // Not NixOS, or the paths are absent. Not an error - just nothing
            // to say.
            return Ok(Vec::new());
        };

        if booted == current {
            return Ok(Vec::new());
        }

        Ok(vec![Action {
            id: "reboot-needed".into(),
            title: "Reboot to run the current generation".into(),
            subject: Subject::NixOS,
            kind: ActionKind::Shell,
            why: format!(
                "The booted system differs from the current one.\n\
                 booted:  {}\n\
                 current: {}",
                booted.display(),
                current.display()
            ),
            info: ActionInfo {
                what: "Restarts the machine so it boots the current generation, \
                       replacing the running kernel, initrd and the services \
                       that were started from the old one.",
                if_wrong: "Not urgent in itself - userspace is already the new \
                           generation. It matters when the difference is a \
                           kernel or driver update, which is also when \
                           something inexplicable tends to be broken.",
            },
            command: "sudo reboot".into(),
            // systemctl rather than the displayed `sudo reboot`: pkexec runs
            // the program directly, and systemctl is the one that exists on a
            // predictable path under a service's environment.
            run: Some(RunCommand {
                program: "systemctl".into(),
                args: vec!["reboot".into()],
                elevate: true,
                cwd: None,
            }),
            effects: vec![
                "Ends every running process and open session".into(),
                "Boots into the current generation".into(),
            ],
            needs_root: true,
            urgency: Urgency::Advised,
        }])
    }
}
