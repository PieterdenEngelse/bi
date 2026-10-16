//! Every interactive control in the UI must carry an info button.
//!
//! This exists because the convention kept being broken in exactly one way:
//! a control gets added during work that is *about* something else - the Run
//! button arrived in the middle of the pkexec work - and the explanation is
//! left for later, which never comes.
//!
//! `every_panel_and_stat_is_explained` already enforces the same rule for the
//! data model: no panel, stat or action ships without what/why/if-wrong. But
//! it checks JSON served by the engine, so a *control* added in QML breaks
//! nothing and nobody notices. This closes that half.
//!
//! It lives in the engine's test directory for the dull reason that this is
//! the only test harness the project has. It reads `../qml` as data and needs
//! nothing from the engine itself.

use std::{collections::BTreeSet, fs, path::Path};

/// How far after a control an info button may appear and still count as
/// belonging to it. Generous: a card's control sits at the top and its info
/// button at the bottom, with the whole layout in between.
const WINDOW: usize = 60;

/// Controls that genuinely have no mechanism to explain, with the reason.
///
/// Keep this list short and argued. "I could not think what to write" means
/// the control needs explaining, not exempting - and if a control truly needs
/// no explanation, that is usually worth a sentence of its own.
const EXEMPT: &[(&str, &str)] = &[
    (
        "Main.qml:‹",
        "A back chevron, shown only when you have drilled into a subject. \
         There is no mechanism behind it: it returns to the overview. An info \
         button here would be noise next to the five that are not.",
    ),
    (
        "ClickOrSelectArea.qml:*",
        "A mechanism rather than a control: it is the press owner a tile lends \
         to its own click-or-select gesture, and it cannot know what the click \
         does. Whatever uses it is the control, and carries the info button \
         that explains the gesture - the subject cards do exactly that.",
    ),
    (
        "CloseX.qml:*",
        "The close X every modal carries. Its mechanism is the whole of its \
         label: it shuts the panel in front of you, and Escape does the same. \
         An info button inside the close control of an info panel would be a \
         panel explaining how to leave itself.",
    ),
    (
        "InfoButton.qml:*",
        "InfoButton IS the explanation mechanism. Its own trigger and its \
         panel's close button cannot explain themselves without recursion.",
    ),
];

fn qml_dir() -> std::path::PathBuf {
    // CARGO_MANIFEST_DIR is engine/; the shared QML tree is its sibling.
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("engine/ has a parent")
        .join("qml")
}

fn is_exempt(file: &str, line: &str) -> bool {
    EXEMPT.iter().any(|(key, _reason)| {
        let (f, marker) = key.split_once(':').expect("exempt key is file:marker");
        f == file && (marker == "*" || line.contains(marker))
    })
}

#[test]
fn every_interactive_control_has_an_info_button() {
    let dir = qml_dir();
    let mut checked = 0;
    let mut failures = Vec::new();

    let files: BTreeSet<_> = fs::read_dir(&dir)
        .unwrap_or_else(|e| panic!("reading {}: {e}", dir.display()))
        .filter_map(|e| e.ok())
        .map(|e| e.file_name().to_string_lossy().to_string())
        .filter(|n| n.ends_with(".qml"))
        .collect();
    // Sanity: if the glob silently matched nothing, the test would pass while
    // checking zero controls - the exact failure mode it is meant to prevent.
    assert!(files.len() > 5, "only found {} QML files", files.len());

    for name in &files {
        let text = fs::read_to_string(dir.join(name)).expect("read qml");
        let lines: Vec<&str> = text.lines().collect();

        for (i, line) in lines.iter().enumerate() {
            let trimmed = line.trim();
            // Declarations only. A comment mentioning MouseArea is not one,
            // and `InfoButton {` must not match as a control needing info.
            if trimmed.starts_with("//") {
                continue;
            }
            let is_control = (trimmed.starts_with("Button {")
                || trimmed.starts_with("TabButton {")
                || trimmed.starts_with("MouseArea {"))
                && !trimmed.starts_with("InfoButton");
            if !is_control {
                continue;
            }
            if is_exempt(name, line) {
                continue;
            }

            checked += 1;
            let end = (i + WINDOW).min(lines.len());
            let has_info = lines[i..end]
                .iter()
                .any(|l| l.trim_start().starts_with("InfoButton {"));

            if !has_info {
                failures.push(format!(
                    "{name}:{} - `{trimmed}` has no InfoButton within {WINDOW} lines.\n    \
                     Adding a control means adding its info panel in the SAME change. \
                     Explain the mechanism, not the label. If it genuinely has no \
                     mechanism, add it to EXEMPT in this file with the reason.",
                    i + 1
                ));
            }
        }
    }

    assert!(checked > 0, "matched no controls - the scanner is broken");
    assert!(
        failures.is_empty(),
        "{} of {checked} controls are unexplained:\n\n{}",
        failures.len(),
        failures.join("\n\n")
    );
}

/// An exemption without a reason is just a silenced test.
#[test]
fn every_exemption_is_argued() {
    for (key, reason) in EXEMPT {
        assert!(
            reason.len() > 60,
            "{key}: exemption reason is {} chars - say why it needs no \
             explanation, or give it one",
            reason.len()
        );
    }
}
