use std::time::SystemTime;

use anyhow::Result;

use super::{Action, ActionInfo, ActionKind, ActionProvider, RunCommand, Urgency};
use crate::collector::Subject;

/// Config edited but never applied.
///
/// Compares the newest mtime under /etc/nixos against the current system
/// generation. Edits that were never rebuilt are easy to forget and silently
/// do nothing, which is a bad failure mode for a config you believe is live.
pub struct ConfigDrift;

fn newest_mtime(dir: &str) -> Result<Option<SystemTime>> {
    let mut newest = None;
    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        // One level is enough: a deep walk of /etc/nixos on every request is
        // not worth it, and top-level .nix files are where edits land.
        if let Ok(meta) = entry.metadata() {
            if let Ok(modified) = meta.modified() {
                newest = Some(match newest {
                    None => modified,
                    Some(n) if modified > n => modified,
                    Some(n) => n,
                });
            }
        }
    }
    Ok(newest)
}

impl ActionProvider for ConfigDrift {
    fn id(&self) -> &'static str {
        "drift"
    }

    fn actions(&self) -> Result<Vec<Action>> {
        if !std::path::Path::new("/etc/nixos").is_dir() {
            return Ok(Vec::new());
        }

        let Some(config_mtime) = newest_mtime("/etc/nixos")? else {
            return Ok(Vec::new());
        };
        // symlink_metadata, NOT metadata: metadata() follows the symlink to the
        // store path, and Nix normalises every store mtime to epoch 1970. That
        // makes any config look newer and this action fire permanently. The
        // activation time is on the symlink itself.
        let Ok(system_meta) = std::fs::symlink_metadata("/run/current-system") else {
            return Ok(Vec::new());
        };
        let Ok(system_mtime) = system_meta.modified() else {
            return Ok(Vec::new());
        };

        if config_mtime <= system_mtime {
            return Ok(Vec::new());
        }

        let ago = config_mtime
            .elapsed()
            .map(|d| format!("{} minutes ago", d.as_secs() / 60))
            .unwrap_or_else(|_| "recently".into());

        Ok(vec![Action {
            id: "config-drift".into(),
            title: "Rebuild - /etc/nixos is newer than the running system".into(),
            subject: Subject::NixOS,
            kind: ActionKind::Shell,
            why: format!(
                "Something under /etc/nixos was edited {ago}, after the current \
                 generation was built. Those edits are not active."
            ),
            info: ActionInfo {
                what: "Builds a new system generation from the current \
                       /etc/nixos and activates it immediately, without \
                       rebooting.",
                if_wrong: "If the edit was a work in progress, this activates \
                           it. Use `nixos-rebuild dry-activate` first to see \
                           what would change, or `build` to compile without \
                           switching.",
            },
            command: "sudo nixos-rebuild switch".into(),
            run: Some(RunCommand {
                program: "nixos-rebuild".into(),
                args: vec!["switch".into()],
                elevate: true,
            }),
            effects: vec![
                "Builds and activates a new generation".into(),
                "Restarts services whose units changed".into(),
                "The previous generation stays available for rollback".into(),
            ],
            needs_root: true,
            urgency: Urgency::Advised,
        }])
    }
}
