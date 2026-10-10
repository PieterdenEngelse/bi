//! nixdash's own configuration, as something the app can change.
//!
//! This is the one place the engine writes a file, and it is deliberately
//! narrow.
//!
//! **It owns one generated file and rewrites it whole.** It does not parse,
//! patch or edit your hand-written Nix. Editing someone's configuration by
//! regex is how comments get eaten and structure quietly rearranged; a file
//! that is wholly generated from validated values cannot be mangled, because
//! nothing is preserved across the write.
//!
//! **Writing changes nothing by itself.** The file is Nix source. It takes
//! effect at the next `home-manager switch`, which is a separate, visible
//! step - so the app reports *declared* and *in effect* as two values and
//! lets you see them disagree. That is the honest model for a declarative
//! system: there is no setting to "apply now", and pretending otherwise
//! would be the lie the Config page was built to avoid.
//!
//! **Only known keys, only known shapes.** The caller names a setting from a
//! fixed list and supplies a value that is range- or enum-checked. There is
//! no path, no fragment, no free text that reaches the file.

use std::path::PathBuf;

use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};

/// What kind of value a setting holds, and what counts as valid.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Kind {
    /// A TCP port. Range-checked, and deliberately excludes privileged ports:
    /// the engine runs as you and could not bind one anyway.
    Port {
        min: u16,
        max: u16,
    },
    Bool,
    /// One of a fixed set of strings.
    Enum {
        options: Vec<&'static str>,
    },
}

/// One setting the app may change.
#[derive(Debug, Clone, Serialize)]
pub struct Setting {
    /// Stable id used by the API.
    pub key: &'static str,
    /// The Nix attribute beneath `services.nixdash`.
    pub attr: &'static str,
    pub label: &'static str,
    #[serde(flatten)]
    pub kind: Kind,
    /// What it does, and what changing it costs.
    pub what: &'static str,
    pub why: &'static str,
    pub if_wrong: &'static str,
}

/// The value of a setting, in the shape its kind demands.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum SettingValue {
    Bool(bool),
    Int(u64),
    Text(String),
}

impl SettingValue {
    /// Render as Nix source. The only place a value becomes text.
    fn to_nix(&self) -> String {
        match self {
            SettingValue::Bool(b) => b.to_string(),
            SettingValue::Int(n) => n.to_string(),
            // Quoted and escaped. Reachable only for Enum settings, whose
            // values are validated against a fixed list first, so this cannot
            // carry arbitrary text - but it escapes anyway rather than relying
            // on that remaining true.
            SettingValue::Text(s) => {
                format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""))
            }
        }
    }
}

/// Every setting the app may write. Adding one here is the only way to make
/// a new value writable.
pub fn known() -> Vec<Setting> {
    vec![
        Setting {
            key: "port",
            attr: "port",
            label: "Engine port",
            kind: Kind::Port {
                min: 1024,
                max: 65535,
            },
            what: "The loopback port the engine listens on, and the port the \
                   desktop UI is told to reach it at.",
            why: "Both halves come from this one value - the service's \
                  NIXDASH_PORT and the UI's launcher - so they cannot drift \
                  apart. Changing it needs a rebuild and a restart before \
                  anything listens on the new port.",
            if_wrong: "Below 1024 is refused: those are privileged ports and \
                       the engine runs as you. If the UI shows a red address \
                       after a change, the service is still on the old port - \
                       restart it.",
        },
        Setting {
            key: "logLevel",
            attr: "logLevel",
            label: "Log level",
            kind: Kind::Enum {
                options: vec!["error", "warn", "info", "debug", "trace"],
            },
            what: "The RUST_LOG level the service runs with. Read it with \
                   `journalctl --user -u nixdash-engine`.",
            why: "debug and trace log every sample from every panel - at the \
                  memory panel's 2 second interval that is a great deal of \
                  journal for very little. info is the useful default; it \
                  still records every action that runs.",
            if_wrong: "trace left on will fill the journal faster than you \
                       expect. It is a diagnostic setting, not a monitoring \
                       one.",
        },
        Setting {
            key: "autoStart",
            attr: "autoStart",
            label: "Start engine at login",
            kind: Kind::Bool,
            what: "Whether the engine service starts automatically when you \
                   log in.",
            why: "The engine is what collects; the window is only a view of \
                  it. Turning this off means no history accumulates unless \
                  you start the service by hand.",
            if_wrong: "Off, with the UI still installed, gives a window that \
                       cannot reach anything and shows a red address.",
        },
        Setting {
            key: "ui.autostart",
            attr: "ui.autostart",
            label: "Open the window at login",
            kind: Kind::Bool,
            what: "Whether the desktop window opens automatically at login.",
            why: "Independent of the engine. Monitoring continues either way - \
                  this only decides whether a window is there to see it.",
            if_wrong: "Off simply means launching it yourself from the panel \
                       icon or the application menu.",
        },
    ]
}

pub fn find(key: &str) -> Option<Setting> {
    known().into_iter().find(|s| s.key == key)
}

/// Check a value against its setting, returning the value to store.
pub fn validate(setting: &Setting, value: &SettingValue) -> Result<SettingValue> {
    match (&setting.kind, value) {
        (Kind::Port { min, max }, SettingValue::Int(n)) => {
            let n = *n;
            if n < *min as u64 || n > *max as u64 {
                bail!("port must be between {min} and {max}, got {n}");
            }
            Ok(SettingValue::Int(n))
        }
        (Kind::Bool, SettingValue::Bool(b)) => Ok(SettingValue::Bool(*b)),
        (Kind::Enum { options }, SettingValue::Text(s)) => {
            if !options.contains(&s.as_str()) {
                bail!(
                    "{} must be one of {}, got {s:?}",
                    setting.key,
                    options.join(", ")
                );
            }
            Ok(SettingValue::Text(s.clone()))
        }
        _ => bail!("{} expects a different kind of value", setting.key),
    }
}

/// Where the generated file lives.
///
/// Overridable so tests never touch a real configuration, and so the path can
/// move on a machine that arranges home-manager differently.
pub fn settings_path() -> Option<PathBuf> {
    if let Ok(p) = std::env::var("NIXDASH_SETTINGS_FILE") {
        return Some(PathBuf::from(p));
    }
    let home = std::env::var("HOME").ok()?;
    Some(PathBuf::from(home).join(".config/home-manager/nixdash-settings.nix"))
}

/// Render a value as it must appear in the file, which is not always what the
/// UI shows.
///
/// `logLevel` is the case that forces this. The module's default is a tuned
/// RUST_LOG directive - `nixdash_engine=info,tower_http=warn` - which keeps
/// HTTP request logging quieter than the engine's own. Writing a bare "info"
/// would silently turn that tuning off and fill the journal with request
/// lines. So the UI offers a simple level and the file gets the directive.
fn to_nix_for(setting: &Setting, value: &SettingValue) -> String {
    match (setting.key, value) {
        ("logLevel", SettingValue::Text(level)) => {
            format!("\"nixdash_engine={level},tower_http=warn\"")
        }
        _ => value.to_nix(),
    }
}

/// The inverse: recover the level the UI shows from what is in the file.
fn from_nix_for(setting: &Setting, raw: &str) -> Option<SettingValue> {
    let unquoted = raw.trim().trim_matches('"');
    match setting.key {
        "logLevel" => {
            // "nixdash_engine=debug,tower_http=warn" -> "debug"; a bare level
            // is accepted too, so a hand-edited file still reads back.
            let level = unquoted
                .split(',')
                .find_map(|part| part.trim().strip_prefix("nixdash_engine="))
                .unwrap_or(unquoted);
            Some(SettingValue::Text(level.to_string()))
        }
        _ => None,
    }
}

/// Declared values, read back from the generated file.
///
/// Parsing is tolerated here only because this file's shape is ours: it is
/// regenerated whole on every write, so the format is known exactly. Nothing
/// attempts to read a hand-written Nix file.
pub fn read_declared(text: &str) -> Vec<(String, SettingValue)> {
    let mut out = Vec::new();
    for setting in known() {
        let needle = format!("{} = ", setting.attr);
        let Some(idx) = text.find(&needle) else {
            continue;
        };
        let rest = &text[idx + needle.len()..];
        let Some(end) = rest.find(';') else { continue };
        let raw = rest[..end].trim();
        let value = match setting.kind {
            Kind::Bool => match raw {
                "true" => Some(SettingValue::Bool(true)),
                "false" => Some(SettingValue::Bool(false)),
                _ => None,
            },
            Kind::Port { .. } => raw.parse::<u64>().ok().map(SettingValue::Int),
            Kind::Enum { .. } => from_nix_for(&setting, raw),
        };
        if let Some(v) = value {
            out.push((setting.key.to_string(), v));
        }
    }
    out
}

/// Render the whole file from a complete set of values.
///
/// Everything is generated, including the warning at the top. A write never
/// merges with what was there, so there is nothing to corrupt.
pub fn render(values: &[(String, SettingValue)]) -> String {
    let mut body = String::new();
    for setting in known() {
        let Some((_, v)) = values.iter().find(|(k, _)| k == setting.key) else {
            continue;
        };
        body.push_str(&format!(
            "    {} = {};\n",
            setting.attr,
            to_nix_for(&setting, v)
        ));
    }

    format!(
        "# Generated by nixdash. This file is rewritten in full whenever a\n\
         # setting is changed from the app - edits made here by hand will be\n\
         # lost the next time that happens.\n\
         #\n\
         # It is imported by modules/nixdash.nix, which holds everything that\n\
         # is NOT a plain value: the prose, the reasoning, and the import of\n\
         # the project's own home-manager module.\n\
         #\n\
         # Writing this file changes nothing on its own. It is Nix source, and\n\
         # takes effect at the next `home-manager switch`.\n\
         {{ ... }}:\n\
         {{\n\
         \x20 services.nixdash = {{\n\
         {body}\x20 }};\n\
         }}\n"
    )
}

/// A single-setting change, with the file content it would produce.
#[derive(Debug, Serialize)]
pub struct Change {
    pub key: String,
    pub from: Option<SettingValue>,
    pub to: SettingValue,
    pub path: String,
    /// The complete new file, for showing before it is written.
    pub rendered: String,
    /// Line-level diff of the generated file.
    pub diff: Vec<String>,
}

/// Compute what a change would do, without touching the filesystem.
pub fn plan(current_text: &str, path: &str, key: &str, value: &SettingValue) -> Result<Change> {
    let Some(setting) = find(key) else {
        bail!("no setting {key}");
    };
    let value = validate(&setting, value)?;

    let mut values = read_declared(current_text);
    let from = values
        .iter()
        .find(|(k, _)| k == key)
        .map(|(_, v)| v.clone());

    // Defaults for anything not yet declared, so the generated file is always
    // complete rather than accumulating keys one write at a time.
    for s in known() {
        if !values.iter().any(|(k, _)| k == s.key) {
            let default = match s.kind {
                Kind::Bool => SettingValue::Bool(true),
                Kind::Port { .. } => SettingValue::Int(3100),
                Kind::Enum { .. } => SettingValue::Text("info".into()),
            };
            values.push((s.key.to_string(), default));
        }
    }
    if let Some(slot) = values.iter_mut().find(|(k, _)| k == key) {
        slot.1 = value.clone();
    }

    let rendered = render(&values);
    let diff = line_diff(current_text, &rendered);

    Ok(Change {
        key: key.to_string(),
        from,
        to: value,
        path: path.to_string(),
        rendered,
        diff,
    })
}

/// Lines that differ, marked. Enough to see a one-value change clearly.
pub(crate) fn line_diff(before: &str, after: &str) -> Vec<String> {
    let old: Vec<&str> = before.lines().collect();
    let new: Vec<&str> = after.lines().collect();
    let mut out = Vec::new();
    for line in &old {
        if !new.contains(line) {
            out.push(format!("- {line}"));
        }
    }
    for line in &new {
        if !old.contains(line) {
            out.push(format!("+ {line}"));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text_with(port: u64) -> String {
        render(&[
            ("port".into(), SettingValue::Int(port)),
            ("logLevel".into(), SettingValue::Text("info".into())),
            ("autoStart".into(), SettingValue::Bool(true)),
            ("ui.autostart".into(), SettingValue::Bool(true)),
        ])
    }

    /// The log level shown and the log level written are not the same string.
    ///
    /// The module's default is a tuned RUST_LOG directive that keeps HTTP
    /// request logging quieter than the engine's own. A bare "info" in the
    /// file would silently discard that tuning, so the UI's simple choice is
    /// expanded on write and contracted on read - and the round trip has to
    /// hold, or the UI would show a level that is not what is running.
    #[test]
    fn the_log_level_round_trips_through_the_tuned_directive() {
        let s = find("logLevel").unwrap();
        let written = to_nix_for(&s, &SettingValue::Text("debug".into()));
        assert_eq!(written, "\"nixdash_engine=debug,tower_http=warn\"");

        let text = render(&[("logLevel".into(), SettingValue::Text("debug".into()))]);
        assert!(text.contains("tower_http=warn"), "tuning lost:\n{text}");

        let back = read_declared(&text);
        assert_eq!(
            back.iter().find(|(k, _)| k == "logLevel").map(|(_, v)| v),
            Some(&SettingValue::Text("debug".into())),
            "did not contract back to the level the UI shows"
        );
    }

    #[test]
    fn a_hand_written_bare_level_still_reads_back() {
        // Someone may edit the file despite the warning; a bare level must
        // not read as garbage.
        let text = "{ ... }:\n{\n  services.nixdash = {\n    logLevel = \"trace\";\n  };\n}\n";
        let back = read_declared(text);
        assert_eq!(
            back.iter().find(|(k, _)| k == "logLevel").map(|(_, v)| v),
            Some(&SettingValue::Text("trace".into()))
        );
    }

    #[test]
    fn a_rendered_file_reads_back_as_what_was_written() {
        let text = text_with(3100);
        let declared = read_declared(&text);
        assert_eq!(
            declared.iter().find(|(k, _)| k == "port").map(|(_, v)| v),
            Some(&SettingValue::Int(3100))
        );
        assert_eq!(
            declared
                .iter()
                .find(|(k, _)| k == "logLevel")
                .map(|(_, v)| v),
            Some(&SettingValue::Text("info".into()))
        );
    }

    #[test]
    fn out_of_range_ports_are_refused() {
        let s = find("port").unwrap();
        assert!(
            validate(&s, &SettingValue::Int(80)).is_err(),
            "privileged port"
        );
        assert!(
            validate(&s, &SettingValue::Int(70000)).is_err(),
            "above range"
        );
        assert!(validate(&s, &SettingValue::Int(3100)).is_ok());
    }

    #[test]
    fn an_unknown_log_level_is_refused() {
        let s = find("logLevel").unwrap();
        assert!(validate(&s, &SettingValue::Text("chatty".into())).is_err());
        assert!(validate(&s, &SettingValue::Text("debug".into())).is_ok());
    }

    #[test]
    fn a_value_of_the_wrong_kind_is_refused() {
        let port = find("port").unwrap();
        assert!(validate(&port, &SettingValue::Bool(true)).is_err());
        let flag = find("autoStart").unwrap();
        assert!(validate(&flag, &SettingValue::Int(1)).is_err());
    }

    #[test]
    fn unknown_keys_cannot_be_written() {
        let err = plan("", "/tmp/x.nix", "evil", &SettingValue::Int(1)).unwrap_err();
        assert!(err.to_string().contains("no setting"));
    }

    #[test]
    fn a_change_shows_only_the_line_that_changed() {
        let before = text_with(3100);
        let change = plan(&before, "/tmp/x.nix", "port", &SettingValue::Int(3200)).unwrap();
        assert_eq!(change.from, Some(SettingValue::Int(3100)));
        assert_eq!(change.diff.len(), 2, "{:?}", change.diff);
        assert!(change
            .diff
            .iter()
            .any(|l| l.starts_with("- ") && l.contains("3100")));
        assert!(change
            .diff
            .iter()
            .any(|l| l.starts_with("+ ") && l.contains("3200")));
    }

    #[test]
    fn a_first_write_produces_every_key_not_just_the_one_set() {
        // Starting from nothing, the file must come out complete - otherwise
        // it would accumulate keys one change at a time and the unset ones
        // would silently take the module's defaults.
        let change = plan("", "/tmp/x.nix", "port", &SettingValue::Int(3300)).unwrap();
        for s in known() {
            assert!(
                change.rendered.contains(&format!("{} = ", s.attr)),
                "missing {} in:\n{}",
                s.attr,
                change.rendered
            );
        }
    }

    #[test]
    fn text_values_are_escaped_even_though_they_are_enum_checked() {
        // Defence in depth: validation already restricts these to a fixed
        // list, but the renderer must not depend on that staying true.
        let v = SettingValue::Text("a\"b\\c".into());
        assert_eq!(v.to_nix(), "\"a\\\"b\\\\c\"");
    }

    #[test]
    fn the_generated_file_says_it_is_generated() {
        // Anyone opening it must know an edit by hand will be lost.
        let text = text_with(3100);
        assert!(text.contains("Generated by nixdash"));
        assert!(text.contains("rewritten in full"));
        assert!(text.contains("home-manager switch"));
    }
}
