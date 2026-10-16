use std::process::Command;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::collector::{Collector, Info, PanelMeta, StatInfo, Status, Subject};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Scope {
    System,
    User,
}

impl Scope {
    pub fn as_str(&self) -> &'static str {
        match self {
            Scope::System => "system",
            Scope::User => "user",
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct FailedUnit {
    pub unit: String,
    pub scope: Scope,
    pub active: String,
    pub sub: String,
    pub description: String,
}

/// The subset of `systemctl list-units --output=json` we care about.
/// Unknown fields are ignored, so a systemd upgrade adding columns is benign.
#[derive(Debug, Deserialize)]
struct SystemctlUnit {
    unit: String,
    #[serde(default)]
    active: String,
    #[serde(default)]
    sub: String,
    #[serde(default)]
    description: String,
}

fn query(scope: Scope) -> Result<Vec<SystemctlUnit>> {
    let mut cmd = Command::new("systemctl");
    if scope == Scope::User {
        cmd.arg("--user");
    }
    cmd.args(["list-units", "--failed", "--output=json", "--no-pager"]);

    let out = cmd.output().context("running systemctl")?;
    if !out.status.success() {
        anyhow::bail!(
            "systemctl ({}) exited {}: {}",
            scope.as_str(),
            out.status,
            String::from_utf8_lossy(&out.stderr).trim()
        );
    }
    // Empty output is not valid JSON but does mean "nothing failed".
    let text = String::from_utf8_lossy(&out.stdout);
    if text.trim().is_empty() {
        return Ok(Vec::new());
    }
    serde_json::from_str(&text).context("parsing systemctl JSON")
}

/// Shared by the panel and the restart actions, so both see the same thing.
/// Returns the failed units plus any scope that could not be queried at all -
/// "nothing failed" and "could not look" must never be confused.
pub fn failed_units() -> (Vec<FailedUnit>, Vec<Scope>) {
    let mut units = Vec::new();
    let mut unavailable = Vec::new();

    for scope in [Scope::System, Scope::User] {
        match query(scope) {
            Ok(found) => units.extend(found.into_iter().map(|u| FailedUnit {
                unit: u.unit,
                scope,
                active: u.active,
                sub: u.sub,
                description: u.description,
            })),
            Err(e) => {
                tracing::debug!(scope = scope.as_str(), error = %e, "scope unavailable");
                unavailable.push(scope);
            }
        }
    }

    (units, unavailable)
}

pub struct FailedUnitsCollector;

#[derive(Debug, Serialize)]
struct FailedUnitsReading {
    count: usize,
    units: Vec<FailedUnit>,
    unavailable_scopes: Vec<&'static str>,
}

impl Collector for FailedUnitsCollector {
    fn meta(&self) -> PanelMeta {
        PanelMeta {
            id: "failed-units",
            title: "Failed units",
            description: "systemd units in a failed state (user and system)",
            interval_secs: 15,
            subject: Subject::NixOS,
            info: Info {
                what: "systemd units currently in the failed state, queried in \
                       both the system and your user scope.",
                why: "A failed unit is silent: nothing tells you a timer, \
                      mount or background service died until you need it.",
                if_wrong: "Any non-zero count deserves `systemctl status` on \
                           the named unit before restarting it - a restart \
                           without reading the failure usually just repeats \
                           it.",
                sections: &[],
            },
            stats: vec![
                StatInfo {
                    key: "count",
                    info: Info {
                        what: "How many units are failed across both scopes.",
                        why: "The single number worth glancing at.",
                        if_wrong: "Zero is the expected state. Anything else \
                                   is worth a look, however boring the unit.",
                        sections: &[],
                    },
                },
                StatInfo {
                    key: "units",
                    info: Info {
                        what: "The failed units, each with its scope, state \
                               and description.",
                        why: "Scope decides who can fix it: a user unit you \
                              restart yourself, a system unit needs root.",
                        if_wrong: "A unit that reappears after a restart is \
                                   failing at start, not having crashed - read \
                                   its journal rather than restarting again.",
                        sections: &[],
                    },
                },
                StatInfo {
                    key: "unavailable_scopes",
                    info: Info {
                        what: "Scopes that could not be queried at all.",
                        why: "\"Nothing failed\" and \"could not look\" must \
                              not render the same. A panel that cannot tell \
                              them apart is worse than no panel.",
                        if_wrong: "A listed scope means the count above is \
                                   incomplete - treat the green tick as \
                                   unverified, not as good news.",
                        sections: &[],
                    },
                },
            ],
        }
    }

    fn sample(&self) -> Result<Value> {
        let (units, unavailable) = failed_units();

        // One scope failing is reported, not fatal. Both failing means
        // systemctl is unusable and the panel should say so.
        if unavailable.len() == 2 {
            anyhow::bail!("systemctl unavailable for both scopes");
        }

        Ok(serde_json::to_value(FailedUnitsReading {
            count: units.len(),
            units,
            unavailable_scopes: unavailable.iter().map(|s| s.as_str()).collect(),
        })?)
    }

    fn status(&self, v: &Value) -> (Status, String) {
        let count = v["count"].as_u64().unwrap_or(0);
        let blind = v["unavailable_scopes"].as_array().map_or(0, |a| a.len());

        // Could-not-look is not good news. Reporting it as Ok would make the
        // green tick mean "nothing failed, probably".
        if blind > 0 {
            return (Status::Unknown, format!("{blind} scope(s) unreadable"));
        }
        if count > 0 {
            (Status::Bad, format!("{count} failed"))
        } else {
            (Status::Ok, "no failed units".into())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_systemctl_json() {
        let json = r#"[{"unit":"foo.service","load":"loaded","active":"failed",
                        "sub":"failed","description":"Foo"}]"#;
        let units: Vec<SystemctlUnit> = serde_json::from_str(json).unwrap();
        assert_eq!(units[0].unit, "foo.service");
        assert_eq!(units[0].active, "failed");
    }

    /// Needs a live systemd. Ignored by default so `nix build` can run the
    /// hermetic tests in its sandbox, where there is no service manager.
    /// Run these with:  cargo test -- --include-ignored
    #[test]
    #[ignore = "requires a running systemd"]
    fn samples_this_machine() {
        let v = FailedUnitsCollector
            .sample()
            .expect("systemctl should be usable");
        assert!(v["count"].as_u64().is_some());
        assert!(v["units"].is_array());
    }

    /// Needs a live systemd - see above.
    #[test]
    #[ignore = "requires a running systemd"]
    fn shared_query_agrees_with_panel() {
        let (units, unavailable) = failed_units();
        assert!(unavailable.len() < 2, "systemctl unusable in both scopes");
        let v = FailedUnitsCollector.sample().unwrap();
        assert_eq!(v["count"].as_u64().unwrap() as usize, units.len());
    }
}
