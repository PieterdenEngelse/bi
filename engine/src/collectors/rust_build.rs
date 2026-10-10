use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

use anyhow::Result;
use serde::Serialize;
use serde_json::Value;

use crate::collector::{Collector, Info, PanelMeta, StatInfo, Status, Subject};

/// Is the engine you are talking to built from the code on disk?
///
/// The toolchain panel beside this one answers "could you compile here". This
/// answers the question that actually bites: **is what is running current?**
///
/// On NixOS that is easy to get wrong in a specific way. A rebuild produces a
/// new store path and rewrites the unit, but systemd does not restart user
/// services automatically here - `startServices = "suggest"` prints the
/// command instead, because restarting them takes xfconf down and kills the
/// Xfce panel. So the old binary keeps serving, from a store path that still
/// exists, answering requests perfectly. Nothing looks wrong.
///
/// Store mtimes are all normalised to 1970, so comparing file timestamps is
/// useless here. What works is comparing the *running process's start time*
/// against the newest source file: if you edited after it started, it cannot
/// contain that edit.
pub struct RustBuildCollector;

fn project_dir() -> Option<PathBuf> {
    if let Ok(dir) = std::env::var("NIXDASH_PROJECT_DIR") {
        let p = PathBuf::from(dir);
        return p.is_dir().then_some(p);
    }
    let home = std::env::var("HOME").ok()?;
    let p = PathBuf::from(home).join("Projects/nixdash");
    p.is_dir().then_some(p)
}

fn secs(t: std::time::SystemTime) -> Option<u64> {
    t.duration_since(UNIX_EPOCH).ok().map(|d| d.as_secs())
}

/// When this process started.
///
/// The mtime of `/proc/self` is the process's start time - simpler and less
/// brittle than parsing field 22 of `/proc/self/stat` and adding it to the
/// boot time from `/proc/stat`.
fn process_started_at() -> Option<u64> {
    secs(std::fs::metadata("/proc/self").ok()?.modified().ok()?)
}

/// Newest `.rs` anywhere under a directory, with its path relative to the root.
fn newest_source(root: &Path, dir: &Path, best: &mut Option<(u64, String)>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(ft) = entry.file_type() else { continue };
        if ft.is_dir() {
            // target/ is build output, not source, and is enormous.
            let name = entry.file_name();
            if name == "target" || name == ".git" {
                continue;
            }
            newest_source(root, &path, best);
        } else if path.extension().and_then(|e| e.to_str()) == Some("rs") {
            let Some(t) = std::fs::metadata(&path)
                .ok()
                .and_then(|m| m.modified().ok())
            else {
                continue;
            };
            let Some(t) = secs(t) else { continue };
            if best.as_ref().is_none_or(|(b, _)| t > *b) {
                let rel = path
                    .strip_prefix(root)
                    .unwrap_or(&path)
                    .display()
                    .to_string();
                *best = Some((t, rel));
            }
        }
    }
}

#[derive(Debug, Serialize)]
struct BuildReading {
    project_dir: Option<String>,
    /// The binary this engine is running from.
    running_exe: Option<String>,
    /// True when that path is in the Nix store - a deployed build rather than
    /// a `cargo run` from the working tree.
    deployed: bool,
    started_at: Option<u64>,
    newest_source_at: Option<u64>,
    newest_source_file: Option<String>,
    /// Source edited after the running process started.
    stale: bool,
    stale_by_secs: Option<u64>,
}

impl Collector for RustBuildCollector {
    fn meta(&self) -> PanelMeta {
        PanelMeta {
            id: "rust-build",
            title: "Build freshness",
            description: "Whether the running engine was built from the current source",
            interval_secs: 30,
            subject: Subject::Rust,
            info: Info {
                what: "Compares the running engine's start time against the \
                       newest .rs file in the project. If you edited source \
                       after this process started, it cannot contain that \
                       edit.",
                why: "A rebuild makes a new store path and rewrites the unit, \
                      but user services are not restarted automatically on \
                      this machine - startServices is set to 'suggest', \
                      because auto-restarting takes xfconf down and kills the \
                      Xfce panel. So the previous binary keeps running and \
                      answering perfectly. Nothing looks wrong, and you debug \
                      a change that was never loaded.",
                if_wrong: "Stale means: run home-manager switch, then the \
                           restart it prints. Timestamps cannot be used \
                           instead of start time here - every mtime in the \
                           Nix store is normalised to 1970, so comparing the \
                           binary's file date against source would make \
                           everything look permanently stale.",
            },
            stats: vec![
                StatInfo {
                    key: "stale",
                    info: Info {
                        what: "True when a source file is newer than the \
                               moment this process started.",
                        why: "The only reliable comparison available. Store \
                              paths carry no useful mtime, and the engine \
                              cannot know which commit it was built from \
                              without embedding one.",
                        if_wrong: "A false positive is possible if you touch \
                                   a file without changing it - git checkout \
                                   does this. Harmless: a restart costs \
                                   seconds and history is in memory only.",
                    },
                },
                StatInfo {
                    key: "stale_by_secs",
                    info: Info {
                        what: "How long ago the newest source edit was, \
                               relative to this process starting.",
                        why: "Distinguishes 'just saved a file' from 'this \
                              has been running against old code all \
                              afternoon'.",
                        if_wrong: "Null when current, or when either \
                                   timestamp could not be read.",
                    },
                },
                StatInfo {
                    key: "newest_source_file",
                    info: Info {
                        what: "Most recently modified .rs file, relative to \
                               the project root.",
                        why: "Says which change is not loaded, which is the \
                              difference between a warning and something \
                              actionable.",
                        if_wrong: "target/ and .git are skipped deliberately; \
                                   build output is not source and scanning it \
                                   would be slow and always newest.",
                    },
                },
                StatInfo {
                    key: "deployed",
                    info: Info {
                        what: "Whether the running binary is a Nix store path \
                               rather than a cargo build from the tree.",
                        why: "A dev run from target/debug is expected to be \
                              ahead of or behind source freely. A deployed \
                              store build going stale is the one that \
                              misleads, because it is the one you forget is \
                              running.",
                        if_wrong: "False while you are iterating with cargo \
                                   run - staleness still reports honestly, it \
                                   just matters less.",
                    },
                },
                StatInfo {
                    key: "running_exe",
                    info: Info {
                        what: "The binary backing this process, from \
                               /proc/self/exe.",
                        why: "The store hash in the path changes on every \
                              rebuild, so comparing it against the unit's \
                              ExecStart shows whether a restart is \
                              outstanding.",
                        if_wrong: "If this differs from `systemctl --user \
                                   show nixdash-engine -p ExecStart`, the \
                                   unit was updated and the process was never \
                                   restarted.",
                    },
                },
                StatInfo {
                    key: "started_at",
                    info: Info {
                        what: "When this process started, from the mtime of \
                               /proc/self.",
                        why: "Used instead of the binary's own timestamp, \
                              which in the Nix store is always 1970.",
                        if_wrong: "A value far in the past with a recent \
                                   deploy is exactly the stale case this \
                                   panel exists for.",
                    },
                },
                StatInfo {
                    key: "newest_source_at",
                    info: Info {
                        what: "Modification time of the newest .rs file.",
                        why: "The other half of the comparison.",
                        if_wrong: "Null means the project directory could not \
                                   be scanned.",
                    },
                },
                StatInfo {
                    key: "project_dir",
                    info: Info {
                        what: "The project being compared against.",
                        why: "Set NIXDASH_PROJECT_DIR to point elsewhere.",
                        if_wrong: "Null means no source tree was found, and \
                                   this panel can say nothing - which it \
                                   reports as unknown rather than as \
                                   'current'.",
                    },
                },
            ],
        }
    }

    fn sample(&self) -> Result<Value> {
        let running_exe = std::fs::read_link("/proc/self/exe")
            .ok()
            .map(|p| p.display().to_string());
        let deployed = running_exe
            .as_deref()
            .is_some_and(|p| p.starts_with("/nix/store/"));
        let started_at = process_started_at();

        let Some(dir) = project_dir() else {
            return Ok(serde_json::to_value(BuildReading {
                project_dir: None,
                running_exe,
                deployed,
                started_at,
                newest_source_at: None,
                newest_source_file: None,
                stale: false,
                stale_by_secs: None,
            })?);
        };

        let mut best = None;
        newest_source(&dir, &dir, &mut best);
        let newest_source_at = best.as_ref().map(|(t, _)| *t);
        let newest_source_file = best.as_ref().map(|(_, f)| f.clone());

        let (stale, stale_by_secs) = match (started_at, newest_source_at) {
            (Some(start), Some(src)) if src > start => (true, Some(src - start)),
            _ => (false, None),
        };

        Ok(serde_json::to_value(BuildReading {
            project_dir: Some(dir.display().to_string()),
            running_exe,
            deployed,
            started_at,
            newest_source_at,
            newest_source_file,
            stale,
            stale_by_secs,
        })?)
    }

    fn status(&self, v: &Value) -> (Status, String) {
        if v["project_dir"].is_null() {
            return (Status::Unknown, "no source tree to compare against".into());
        }
        let deployed = v["deployed"].as_bool().unwrap_or(false);
        let kind = if deployed { "deployed" } else { "dev build" };

        if v["stale"].as_bool().unwrap_or(false) {
            let mins = v["stale_by_secs"].as_u64().unwrap_or(0) / 60;
            let file = v["newest_source_file"].as_str().unwrap_or("source");
            let ago = if mins >= 120 {
                format!("{} hours", mins / 60)
            } else {
                format!("{mins} min")
            };
            // Warn, not Bad: the running build is fine, it is simply not the
            // one you just wrote. Nothing is broken until you expect
            // otherwise.
            return (
                Status::Warn,
                format!("{kind} predates {file} by {ago} - restart to pick it up"),
            );
        }

        (Status::Ok, format!("{kind}, current with source"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn process_start_time_is_plausible() {
        let started = process_started_at().expect("/proc/self must be readable");
        let now = secs(std::time::SystemTime::now()).unwrap();
        assert!(started <= now, "started in the future: {started} > {now}");
        // A test process is seconds old, not years. Guards against the mtime
        // of /proc/self turning out to mean something else.
        assert!(now - started < 86_400, "start time looks wrong: {started}");
    }

    #[test]
    fn build_output_is_not_mistaken_for_source() {
        let Some(dir) = project_dir() else { return };
        let mut best = None;
        newest_source(&dir, &dir, &mut best);
        if let Some((_, file)) = best {
            assert!(
                !file.starts_with("target/") && !file.contains("/target/"),
                "scanned build output: {file}"
            );
        }
    }

    #[test]
    fn staleness_needs_both_timestamps() {
        let v = RustBuildCollector.sample().unwrap();
        if v["started_at"].is_null() || v["newest_source_at"].is_null() {
            assert_eq!(v["stale"], Value::Bool(false));
            assert!(v["stale_by_secs"].is_null());
        }
    }

    #[test]
    fn a_missing_project_is_unknown_not_current() {
        // The dangerous failure is reporting "current" when nothing was
        // actually compared.
        let v = serde_json::json!({ "project_dir": Value::Null });
        let (status, _) = RustBuildCollector.status(&v);
        assert_eq!(status, Status::Unknown);
    }
}
