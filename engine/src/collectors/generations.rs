use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

use anyhow::Result;
use serde::Serialize;
use serde_json::Value;

use crate::collector::{Collector, Info, PanelMeta, StatInfo, Status, Subject};

/// System generations, and whether the one you booted is the one you are
/// configured to be running.
///
/// This is the panel that answers "what changed, when, and can I go back".
/// Generation count also informs the GC decision: `nix-collect-garbage -d`
/// deletes every entry here except the current one.
pub struct GenerationsCollector;

const PROFILES: &str = "/nix/var/nix/profiles";

#[derive(Debug, Serialize)]
struct Generation {
    number: u64,
    /// Milliseconds since epoch, from the *symlink* mtime.
    at: u64,
    current: bool,
}

#[derive(Debug, Serialize)]
struct GenerationsReading {
    count: usize,
    current: Option<u64>,
    /// True when /run/booted-system and /run/current-system differ, i.e. the
    /// running kernel/initrd is not the current generation's.
    reboot_needed: bool,
    generations: Vec<Generation>,
}

/// mtime of the symlink itself.
///
/// `std::fs::metadata` would follow it into the store, where Nix normalises
/// every mtime to epoch 1970 - so it must be `symlink_metadata`. The same
/// mistake made the config-drift action fire permanently; see actions/drift.rs.
fn link_mtime_ms(path: &Path) -> Option<u64> {
    let meta = std::fs::symlink_metadata(path).ok()?;
    let modified = meta.modified().ok()?;
    modified
        .duration_since(UNIX_EPOCH)
        .ok()
        .map(|d| d.as_millis() as u64)
}

/// `system-42-link` -> 42
fn generation_number(name: &str) -> Option<u64> {
    name.strip_prefix("system-")?
        .strip_suffix("-link")?
        .parse()
        .ok()
}

impl Collector for GenerationsCollector {
    fn meta(&self) -> PanelMeta {
        PanelMeta {
            id: "generations",
            title: "Generations",
            description: "System generations, and whether a reboot is pending",
            // Changes only on rebuild; polling faster would be pure waste.
            interval_secs: 60,
            subject: Subject::NixOS,
            info: Info {
                what: "Every system configuration NixOS has built, newest \
                       first, plus whether the one you booted is the one \
                       currently configured.",
                why: "Generations are what makes a bad rebuild recoverable: \
                      each is a complete, bootable system you can roll back \
                      to or select at the boot menu.",
                if_wrong: "They cost almost nothing while they share a nixpkgs \
                           revision, so a long list is history, not a problem \
                           - until the disk panel complains.",
            },
            stats: vec![
                StatInfo {
                    key: "count",
                    info: Info {
                        what: "How many generations exist.",
                        why: "How far back you can roll, and what a garbage \
                              collection with -d would delete.",
                        if_wrong: "A large number is harmless unless disk is \
                                   tight; generations sharing a nixpkgs \
                                   revision share nearly all their content.",
                    },
                },
                StatInfo {
                    key: "current",
                    info: Info {
                        what: "The generation /nix/var/nix/profiles/system \
                               points at.",
                        why: "This is what the next boot will use, and what \
                              `nixos-rebuild switch` just produced.",
                        if_wrong: "If this is not the highest number, \
                                   something rolled back - deliberately or \
                                   not.",
                    },
                },
                StatInfo {
                    key: "reboot_needed",
                    info: Info {
                        what: "True when /run/booted-system and \
                               /run/current-system differ.",
                        why: "A rebuild switches the current system \
                              immediately, but the running kernel, initrd and \
                              some services stay as booted until you restart.",
                        if_wrong: "True means you are running a mix: userspace \
                                   from the new generation, kernel from the \
                                   old. Usually fine, occasionally the reason \
                                   something inexplicable is broken.",
                    },
                },
                StatInfo {
                    key: "generations",
                    info: Info {
                        what: "The list, each with its number and the time it \
                               was activated.",
                        why: "Timestamps come from the symlink, not its target \
                              - store paths all carry a 1970 mtime, so the \
                              target would tell you nothing.",
                        if_wrong: "A gap in the numbering means generations \
                                   were collected; you cannot roll back past \
                                   the oldest one shown.",
                    },
                },
            ],
        }
    }

    fn sample(&self) -> Result<Value> {
        let dir = Path::new(PROFILES);
        if !dir.is_dir() {
            anyhow::bail!("{PROFILES} not found - not a NixOS system?");
        }

        let current_target = std::fs::read_link(PathBuf::from(PROFILES).join("system")).ok();

        let mut generations: Vec<Generation> = std::fs::read_dir(dir)?
            .filter_map(|e| e.ok())
            .filter_map(|entry| {
                let name = entry.file_name().into_string().ok()?;
                let number = generation_number(&name)?;
                let at = link_mtime_ms(&entry.path())?;
                let current = current_target.as_deref() == Some(Path::new(&name));
                Some(Generation {
                    number,
                    at,
                    current,
                })
            })
            .collect();

        // Newest first: the ones you might roll back to are the ones you just left.
        generations.sort_by_key(|g| std::cmp::Reverse(g.number));

        let booted = std::fs::read_link("/run/booted-system").ok();
        let running = std::fs::read_link("/run/current-system").ok();
        // Only claim a reboot is needed when BOTH are readable and differ -
        // absent paths must not be reported as a pending reboot.
        let reboot_needed = match (booted, running) {
            (Some(b), Some(c)) => b != c,
            _ => false,
        };

        Ok(serde_json::to_value(GenerationsReading {
            count: generations.len(),
            current: generations.iter().find(|g| g.current).map(|g| g.number),
            reboot_needed,
            generations,
        })?)
    }

    fn status(&self, v: &Value) -> (Status, String) {
        let count = v["count"].as_u64().unwrap_or(0);
        let reboot = v["reboot_needed"].as_bool().unwrap_or(false);
        let current = v["current"].as_u64();

        // A long list is history, not a problem - the disk panel is what
        // decides whether it has become one.
        let status = if reboot { Status::Warn } else { Status::Ok };
        let head = match current {
            Some(n) if reboot => format!("gen #{n}, reboot pending"),
            Some(n) => format!("{count} generations, on #{n}"),
            None => format!("{count} generations"),
        };
        (status, head)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_generation_names() {
        assert_eq!(generation_number("system-42-link"), Some(42));
        assert_eq!(generation_number("system-1-link"), Some(1));
        assert_eq!(generation_number("system"), None);
        assert_eq!(generation_number("home-manager-3-link"), None);
        assert_eq!(generation_number("system-abc-link"), None);
    }

    #[test]
    fn link_mtime_is_the_symlink_not_the_target() {
        // Guards the bug this file documents: store targets are epoch 1970,
        // so a value near "now" proves the symlink itself was read.
        let Ok(link) = std::fs::read_link("/run/current-system") else {
            return; // not NixOS; nothing to assert
        };
        let _ = link;
        if let Some(ms) = link_mtime_ms(Path::new("/run/current-system")) {
            let now = std::time::SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_millis() as u64;
            assert!(
                ms > 1_000_000_000_000,
                "got epoch-ish mtime {ms}: followed the symlink"
            );
            assert!(ms <= now + 60_000);
        }
    }

    #[test]
    #[ignore = "requires /nix/var/nix/profiles"]
    fn samples_this_machine() {
        let v = GenerationsCollector.sample().expect("should read profiles");
        assert!(v["count"].as_u64().unwrap() > 0);
        assert!(v["generations"].is_array());
    }
}
