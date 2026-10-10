use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::Result;
use serde::Serialize;
use serde_json::Value;

use crate::collector::{Collector, Info, PanelMeta, StatInfo, Status, Subject};

/// The Qt development setup, judged by whether it will actually work.
///
/// Not "is Qt installed" - that is easy and uninteresting. The question that
/// costs hours on NixOS is whether the qmake you are pointed at reports a
/// *complete* prefix. cxx-qt interrogates one qmake for headers, libs AND host
/// tools, but nixpkgs splits those across store paths: qmltyperegistrar and
/// qmlcachegen ship in qtdeclarative, not qtbase. A prefix missing them builds
/// fine right up until it does not.
///
/// This panel answers that question directly instead of leaving you to
/// discover it from a link error.
pub struct QtCollector;

/// Host tools cxx-qt needs. Absence of any one of these means the prefix is
/// split and a cxx-qt build will fail - see ~/docs/qt.md, Part 1.
const REQUIRED_TOOLS: &[&str] = &["moc", "rcc", "qmltyperegistrar", "qmlcachegen"];

#[derive(Debug, Serialize)]
struct QtReading {
    /// Where the qmake came from: the QMAKE env var, or PATH.
    source: &'static str,
    qmake: Option<String>,
    version: Option<String>,
    prefix: Option<String>,
    host_libexecs: Option<String>,
    /// e.g. "linux-g++" or "wasm-emscripten"
    target_spec: Option<String>,
    /// Host tools present in QT_HOST_LIBEXECS.
    tools_found: Vec<String>,
    /// Host tools that are missing - the ones that break cxx-qt.
    tools_missing: Vec<String>,
    /// True when every required tool resolves from this one prefix.
    prefix_complete: bool,
}

fn qmake_query(qmake: &Path, key: &str) -> Option<String> {
    let out = Command::new(qmake).args(["-query", key]).output().ok()?;
    if !out.status.success() {
        return None;
    }
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if s.is_empty() || s == "**Unknown**" {
        None
    } else {
        Some(s)
    }
}

/// Prefer an explicit QMAKE over PATH: that is the one a build will use, and
/// reporting on a different qmake than the build uses would be worse than
/// reporting nothing.
fn find_qmake() -> Option<(&'static str, PathBuf)> {
    if let Ok(q) = std::env::var("QMAKE") {
        let p = PathBuf::from(q);
        if p.is_file() {
            return Some(("QMAKE env var", p));
        }
    }
    let path = std::env::var("PATH").ok()?;
    for dir in path.split(':') {
        for name in ["qmake6", "qmake"] {
            let p = Path::new(dir).join(name);
            if p.is_file() {
                return Some(("PATH", p));
            }
        }
    }
    None
}

impl Collector for QtCollector {
    fn meta(&self) -> PanelMeta {
        PanelMeta {
            id: "qt",
            title: "Qt",
            description: "Which Qt a build would use, and whether its prefix is complete",
            // Only changes when you enter a different shell.
            interval_secs: 60,
            subject: Subject::Qt,
            info: Info {
                what: "The qmake a build would use, and whether the prefix it \
                       reports contains every host tool cxx-qt needs. This is \
                       about BUILDING Qt software - it says nothing about \
                       whether Qt is installed or running.",
                why: "cxx-qt interrogates ONE qmake for headers, libraries and \
                      host tools. nixpkgs splits those across store paths - \
                      qmltyperegistrar and qmlcachegen ship in qtdeclarative, \
                      not qtbase - so a qtbase-only prefix looks fine and then \
                      fails.",
                if_wrong: "'No qmake on PATH' does NOT mean Qt is absent. \
                           nixdash itself is a Qt program and is drawing this \
                           text with libQt6Qml right now: runtime libraries \
                           come from the binary's own Nix closure, found by \
                           RPATH, never from PATH. qmake is a development \
                           tool, which on NixOS normally exists only inside a \
                           devShell - so this panel reads 'unknown' on a \
                           perfectly healthy machine, and that is correct. \
                           An incomplete prefix, by contrast, fails late \
                           during code generation with an error naming the \
                           missing tool rather than the real cause: use \
                           pkgs.qt6.env for a merged prefix, since a plain \
                           symlinkJoin is ignored - nixpkgs' qmake has its \
                           prefix baked in.",
            },
            stats: vec![
                StatInfo {
                    key: "source",
                    info: Info {
                        what: "Where the qmake was found: the QMAKE \
                               environment variable, or PATH.",
                        why: "QMAKE wins if set, and that is what a build \
                              uses. Reporting on a different qmake than the \
                              build uses would be worse than reporting \
                              nothing.",
                        if_wrong: "\"not found\" means no Qt build could run \
                                   here - it does not mean Qt is absent. \
                                   Installed Qt programs keep working, \
                                   including this one: they load their \
                                   libraries by RPATH from their own closure, \
                                   not from PATH.",
                    },
                },
                StatInfo {
                    key: "qmake",
                    info: Info {
                        what: "Full path to the qmake being queried.",
                        why: "A store path tells you which derivation provided \
                              it - a merged env, plain qtbase, or a cross \
                              build.",
                        if_wrong: "If this points at qtbase alone, expect the \
                                   missing-tools problem below.",
                    },
                },
                StatInfo {
                    key: "version",
                    info: Info {
                        what: "QT_VERSION as that qmake reports it.",
                        why: "Host and target Qt must match exactly when \
                              cross-compiling, and each Qt release pins a \
                              specific Emscripten version for WebAssembly.",
                        if_wrong: "A mismatch between host and target Qt fails \
                                   the cross build immediately.",
                    },
                },
                StatInfo {
                    key: "prefix",
                    info: Info {
                        what: "QT_INSTALL_PREFIX - the root this qmake reports \
                               for headers and libraries.",
                        why: "On NixOS this is the single most informative \
                              value: it reveals whether you have one coherent \
                              Qt or several.",
                        if_wrong: "A prefix that is a bare qtbase store path \
                                   cannot satisfy a QML build.",
                    },
                },
                StatInfo {
                    key: "host_libexecs",
                    info: Info {
                        what: "QT_HOST_LIBEXECS - where moc, rcc and friends \
                               live.",
                        why: "This is the directory actually checked for the \
                              required tools.",
                        if_wrong: "Null means qmake could not say, and no tool \
                                   check was possible.",
                    },
                },
                StatInfo {
                    key: "target_spec",
                    info: Info {
                        what: "QMAKE_XSPEC - the platform this Qt builds for.",
                        why: "Distinguishes a host Qt (linux-g++) from a \
                              cross-compiled one (wasm-emscripten).",
                        if_wrong: "Seeing wasm-emscripten when you meant to \
                                   build a desktop app means QMAKE points at \
                                   the wasm SDK.",
                    },
                },
                StatInfo {
                    key: "tools_found",
                    info: Info {
                        what: "Required host tools present in this prefix.",
                        why: "moc and rcc come with qtbase; qmltyperegistrar \
                              and qmlcachegen only with qtdeclarative.",
                        if_wrong: "Two of four is the classic split-prefix \
                                   signature.",
                    },
                },
                StatInfo {
                    key: "tools_missing",
                    info: Info {
                        what: "Required host tools this prefix does not have.",
                        why: "Each one here is a build failure waiting to \
                              happen.",
                        if_wrong: "Non-empty means a cxx-qt QML build will \
                                   fail. Merge the prefix rather than adding \
                                   more entries to buildInputs.",
                    },
                },
                StatInfo {
                    key: "prefix_complete",
                    info: Info {
                        what: "True when all four required tools resolve from \
                               this one prefix.",
                        why: "The verdict the whole panel exists for: will a \
                              cxx-qt build work here?",
                        if_wrong: "False is not a warning, it is a prediction \
                                   of failure.",
                    },
                },
            ],
        }
    }

    fn sample(&self) -> Result<Value> {
        let Some((source, qmake)) = find_qmake() else {
            return Ok(serde_json::to_value(QtReading {
                source: "not found",
                qmake: None,
                version: None,
                prefix: None,
                host_libexecs: None,
                target_spec: None,
                tools_found: Vec::new(),
                tools_missing: REQUIRED_TOOLS.iter().map(|s| s.to_string()).collect(),
                prefix_complete: false,
            })?);
        };

        let version = qmake_query(&qmake, "QT_VERSION");
        let prefix = qmake_query(&qmake, "QT_INSTALL_PREFIX");
        let host_libexecs = qmake_query(&qmake, "QT_HOST_LIBEXECS");
        let target_spec = qmake_query(&qmake, "QMAKE_XSPEC");

        let (found, missing): (Vec<String>, Vec<String>) = match &host_libexecs {
            Some(dir) => REQUIRED_TOOLS
                .iter()
                .map(|t| (t.to_string(), Path::new(dir).join(t).exists()))
                .fold((vec![], vec![]), |(mut f, mut m), (t, exists)| {
                    if exists {
                        f.push(t)
                    } else {
                        m.push(t)
                    }
                    (f, m)
                }),
            None => (
                Vec::new(),
                REQUIRED_TOOLS.iter().map(|s| s.to_string()).collect(),
            ),
        };

        Ok(serde_json::to_value(QtReading {
            source,
            qmake: Some(qmake.display().to_string()),
            version,
            prefix,
            host_libexecs,
            target_spec,
            prefix_complete: missing.is_empty(),
            tools_found: found,
            tools_missing: missing,
        })?)
    }

    fn status(&self, v: &Value) -> (Status, String) {
        let complete = v["prefix_complete"].as_bool().unwrap_or(false);
        let version = v["version"].as_str();

        // No qmake here is not a fault - most shells have none, and flagging
        // it red would make the panel cry wolf everywhere except a Qt dev
        // shell. It is only Bad when a qmake exists but its prefix cannot
        // satisfy a build, because that is the case that fails late and
        // confusingly.
        //
        // The headline says *qmake*, deliberately, and not "no Qt". This
        // panel is about whether you could BUILD Qt software here, and the
        // only thing it looked for is the build tool. Qt's runtime libraries
        // are a separate question it never asked - and the answer is plainly
        // yes, since the app asking it is itself a Qt program. Saying "no Qt
        // in this environment" while rendering through libQt6Qml was simply
        // false, and the kind of false that teaches someone the wrong model.
        match (version, complete) {
            (Some(ver), true) => (Status::Ok, format!("{ver}, prefix complete")),
            (Some(ver), false) => {
                let missing = v["tools_missing"].as_array().map_or(0, |a| a.len());
                (
                    Status::Bad,
                    format!("{ver}, {missing} host tool(s) missing"),
                )
            }
            (None, _) => (
                Status::Unknown,
                "no qmake on PATH - cannot tell whether a Qt build would work".into(),
            ),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reports_absence_without_failing() {
        // No Qt is a legitimate state, not an error: most shells have none.
        // The panel must say so rather than erroring, or it is noise on every
        // machine that is not mid-Qt-build.
        let v = QtCollector.sample().expect("absence is not an error");
        assert!(v["prefix_complete"].as_bool().is_some());
        assert!(v["tools_missing"].is_array());
    }

    #[test]
    fn missing_tools_mean_incomplete() {
        // The invariant the panel exists for.
        let v = QtCollector.sample().unwrap();
        let missing = v["tools_missing"].as_array().unwrap().len();
        let complete = v["prefix_complete"].as_bool().unwrap();
        assert_eq!(complete, missing == 0);
    }
}
