use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::Result;
use serde::Serialize;
use serde_json::Value;

use crate::collector::{Collector, Info, PanelMeta, StatInfo, Status, Subject};

/// The Rust toolchain, judged by what it can actually build.
///
/// A version number alone does not tell you whether `cargo build --target
/// wasm32-unknown-emscripten` will work. nixpkgs' rustc ships std for the host
/// only, so a cross target fails with "can't find crate for `std`" - and the
/// fix (a fenix toolchain) is invisible from `rustc --version`. This panel
/// reports the installed target std libraries instead, which is the thing that
/// decides.
///
/// It also notes `lld`, because wasm32-unknown-unknown needs it and its
/// absence surfaces as `linker 'lld' not found` rather than anything about
/// targets.
pub struct RustCollector;

#[derive(Debug, Serialize)]
struct RustReading {
    rustc: Option<String>,
    cargo: Option<String>,
    /// Resolved rustc path - distinguishes a nixpkgs toolchain from a fenix
    /// one, which is otherwise guesswork.
    rustc_path: Option<String>,
    /// Target std libraries actually installed.
    targets: Vec<String>,
    host_target: Option<String>,
    /// wasm32-unknown-unknown needs lld; absent, the error names the linker
    /// rather than the target.
    lld_available: bool,
    /// Convenience flags for the two wasm targets, since those are the ones
    /// that differ between a nixpkgs and a fenix toolchain.
    has_wasm32_unknown: bool,
    has_wasm32_emscripten: bool,
}

fn first_line(cmd: &str, args: &[&str]) -> Option<String> {
    let out = Command::new(cmd).args(args).output().ok()?;
    if !out.status.success() {
        return None;
    }
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .next()
        .map(|s| s.trim().to_string())
}

fn which(bin: &str) -> Option<PathBuf> {
    let path = std::env::var("PATH").ok()?;
    path.split(':')
        .map(|d| Path::new(d).join(bin))
        .find(|p| p.is_file())
}

/// Installed target std libraries, from `<sysroot>/lib/rustlib/`.
///
/// Read from disk rather than `rustc --print target-list`, which lists every
/// target rustc *knows about* - thousands - not the ones it can link.
fn installed_targets() -> (Vec<String>, Option<PathBuf>) {
    let Some(sysroot) = first_line("rustc", &["--print", "sysroot"]).map(PathBuf::from) else {
        return (Vec::new(), None);
    };
    let rustlib = sysroot.join("lib/rustlib");
    let Ok(entries) = std::fs::read_dir(&rustlib) else {
        return (Vec::new(), Some(sysroot));
    };

    let mut targets: Vec<String> = entries
        .filter_map(|e| e.ok())
        .filter(|e| e.path().join("lib").is_dir())
        .filter_map(|e| e.file_name().into_string().ok())
        .collect();
    targets.sort();
    (targets, Some(sysroot))
}

impl Collector for RustCollector {
    fn meta(&self) -> PanelMeta {
        PanelMeta {
            id: "rust",
            title: "Rust",
            description: "Toolchain and the target std libraries it can actually build for",
            interval_secs: 60,
            subject: Subject::Rust,
            info: Info {
                what: "The rustc and cargo on PATH, where they came from, and \
                       which target standard libraries are actually installed.",
                why: "A version number does not tell you what you can build. \
                      nixpkgs' rustc ships std for the host only, so a cross \
                      target fails with \"can't find crate for std\" - and the \
                      fix is invisible from `rustc --version`.",
                if_wrong: "If a target you need is absent, add it with a fenix \
                           toolchain in the dev shell rather than reaching for \
                           rustup, which fights Nix.",
            },
            stats: vec![
                StatInfo {
                    key: "rustc",
                    info: Info {
                        what: "`rustc --version`.",
                        why: "Edition and feature availability follow from it.",
                        if_wrong: "A surprising version usually means a dev \
                                   shell is or is not active.",
                    },
                },
                StatInfo {
                    key: "cargo",
                    info: Info {
                        what: "`cargo --version`.",
                        why: "Normally tracks rustc; a mismatch suggests two \
                              toolchains are mixed on PATH.",
                        if_wrong: "Differing major versions between rustc and \
                                   cargo is worth untangling before trusting \
                                   a build.",
                    },
                },
                StatInfo {
                    key: "rustc_path",
                    info: Info {
                        what: "The resolved store path of rustc.",
                        why: "This is how you tell a nixpkgs toolchain \
                              (…-rustc-wrapper-…) from a fenix one \
                              (…-rust-mixed…) - otherwise guesswork.",
                        if_wrong: "If you expected fenix and see the nixpkgs \
                                   wrapper, the dev shell is not active.",
                    },
                },
                StatInfo {
                    key: "host_target",
                    info: Info {
                        what: "The triple rustc builds for by default.",
                        why: "Everything else is a cross compile.",
                        if_wrong: "Rarely wrong; informative when comparing \
                                   against the installed target list.",
                    },
                },
                StatInfo {
                    key: "targets",
                    info: Info {
                        what: "Target std libraries actually installed, read \
                               from <sysroot>/lib/rustlib.",
                        why: "Read from disk rather than `rustc --print \
                              target-list`, which lists every target rustc \
                              knows about - thousands - not the ones it can \
                              link.",
                        if_wrong: "A short list is normal. The question is \
                                   only whether the target you need is in it.",
                    },
                },
                StatInfo {
                    key: "lld_available",
                    info: Info {
                        what: "Whether an lld linker is on PATH.",
                        why: "wasm32-unknown-unknown links with lld; without \
                              it the build fails naming the linker, not the \
                              target, which sends you looking in the wrong \
                              place.",
                        if_wrong: "False plus a wasm32-unknown-unknown build \
                                   means adding `lld` to the dev shell - one \
                                   package, not a toolchain change.",
                    },
                },
                StatInfo {
                    key: "has_wasm32_unknown",
                    info: Info {
                        what: "Whether wasm32-unknown-unknown std is \
                               installed.",
                        why: "The target for browser WebAssembly that does not \
                              need Emscripten - Slint and wasm-bindgen use it.",
                        if_wrong: "Present in nixpkgs' rustc, so absence \
                                   suggests a minimal or custom toolchain.",
                    },
                },
                StatInfo {
                    key: "has_wasm32_emscripten",
                    info: Info {
                        what: "Whether wasm32-unknown-emscripten std is \
                               installed.",
                        why: "The target Qt for WebAssembly requires. nixpkgs \
                              does NOT ship it; fenix does.",
                        if_wrong: "False means a Qt-wasm build fails with \
                                   \"can't find crate for std\" before it \
                                   compiles a line of your code.",
                    },
                },
            ],
        }
    }

    fn sample(&self) -> Result<Value> {
        let (targets, _sysroot) = installed_targets();
        let host_target = first_line("rustc", &["-vV"]).and_then(|_| {
            Command::new("rustc")
                .arg("-vV")
                .output()
                .ok()
                .and_then(|o| {
                    String::from_utf8_lossy(&o.stdout)
                        .lines()
                        .find_map(|l| l.strip_prefix("host: ").map(str::to_string))
                })
        });

        Ok(serde_json::to_value(RustReading {
            rustc: first_line("rustc", &["--version"]),
            cargo: first_line("cargo", &["--version"]),
            rustc_path: which("rustc").map(|p| {
                std::fs::canonicalize(&p).unwrap_or(p).display().to_string()
            }),
            lld_available: which("lld").is_some() || which("rust-lld").is_some(),
            has_wasm32_unknown: targets.iter().any(|t| t == "wasm32-unknown-unknown"),
            has_wasm32_emscripten: targets.iter().any(|t| t == "wasm32-unknown-emscripten"),
            host_target,
            targets,
        })?)
    }

    fn status(&self, v: &Value) -> (Status, String) {
        let Some(rustc) = v["rustc"].as_str() else {
            return (Status::Unknown, "no Rust in this environment".into());
        };
        let ver = rustc.split_whitespace().nth(1).unwrap_or(rustc);
        let em = v["has_wasm32_emscripten"].as_bool().unwrap_or(false);
        let wasm = v["has_wasm32_unknown"].as_bool().unwrap_or(false);
        let lld = v["lld_available"].as_bool().unwrap_or(false);

        // A toolchain lacking a target is not broken - it is simply not the
        // one for that target, so Warn rather than Bad. wasm32-unknown-unknown
        // without lld IS broken: it will fail at link, naming the linker.
        let status = if wasm && !lld {
            Status::Warn
        } else if !em && !wasm {
            Status::Warn
        } else {
            Status::Ok
        };

        let head = if em {
            format!("{ver} · emscripten target")
        } else {
            format!("{ver} · no emscripten target")
        };
        (status, head)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reports_absence_without_failing() {
        // No Rust is a legitimate state; the panel says so rather than erroring.
        let v = RustCollector.sample().expect("absence is not an error");
        assert!(v["targets"].is_array());
        assert!(v["lld_available"].as_bool().is_some());
    }

    #[test]
    fn target_flags_agree_with_the_list() {
        let v = RustCollector.sample().unwrap();
        let targets: Vec<&str> = v["targets"]
            .as_array()
            .unwrap()
            .iter()
            .map(|t| t.as_str().unwrap())
            .collect();
        assert_eq!(
            v["has_wasm32_emscripten"].as_bool().unwrap(),
            targets.contains(&"wasm32-unknown-emscripten")
        );
    }

    #[test]
    fn lists_only_targets_with_a_lib_dir() {
        // `rustc --print target-list` would give thousands; this must reflect
        // what is installed, which is a far shorter list.
        let (targets, _) = installed_targets();
        assert!(targets.len() < 50, "got {} targets - reading the wrong thing", targets.len());
    }
}
