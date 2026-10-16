//! Every modal in the UI must carry a visible way out.
//!
//! `Popup` and `Dialog` both close on Escape, and these are all configured to
//! close on a click outside as well. Neither is visible. A panel that covers
//! the window with no exit you can see reads as a hang, and "press Escape" is
//! only obvious to someone who already knows it - which is the wrong
//! assumption anywhere, and a worse one in an app whose purpose is explaining
//! this machine to someone still learning it.
//!
//! So the rule is: anything that covers the window has a close control in its
//! top-right corner, and that control is `CloseX`.
//!
//! Enforced the same way and for the same reason as the info-button rule next
//! door: the convention breaks when a modal is added during work that is
//! *about* something else, and nobody notices because nothing fails.
//!
//! It lives in the engine's test directory because that is the only test
//! harness the project has. It reads `../qml` as data.

use std::{collections::BTreeSet, fs, path::Path};

/// Modals that are deliberately without one, with the reason.
///
/// Empty, and worth keeping that way. A modal with no way out needs a better
/// argument than "it is small".
const EXEMPT: &[(&str, &str)] = &[];

fn qml_dir() -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("engine/ has a parent")
        .join("qml")
}

/// Declarations only - a comment mentioning Popup is not one, and neither is
/// `closePolicy: Popup.CloseOnEscape`, which is why this matches the brace.
fn is_modal_declaration(trimmed: &str) -> bool {
    !trimmed.starts_with("//")
        && (trimmed.starts_with("Popup {") || trimmed.starts_with("Dialog {"))
}

#[test]
fn every_modal_has_a_close_control() {
    let dir = qml_dir();
    let mut modals = 0;
    let mut failures = Vec::new();

    let files: BTreeSet<_> = fs::read_dir(&dir)
        .unwrap_or_else(|e| panic!("reading {}: {e}", dir.display()))
        .filter_map(|e| e.ok())
        .map(|e| e.file_name().to_string_lossy().to_string())
        .filter(|n| n.ends_with(".qml"))
        .collect();
    assert!(files.len() > 5, "only found {} QML files", files.len());

    for name in &files {
        if EXEMPT.iter().any(|(f, _)| f == name) {
            continue;
        }
        let text = fs::read_to_string(dir.join(name)).expect("read qml");

        // Counted per file rather than within a line window of each modal.
        // A window would have to be large enough for InfoButton's panel,
        // whose close control sits ~60 lines below the Popup it belongs to,
        // and at that size it stops being evidence of anything. Counting
        // means a file with two modals needs two close controls, which is
        // the property actually worth holding.
        let found = text
            .lines()
            .filter(|l| is_modal_declaration(l.trim()))
            .count();
        if found == 0 {
            continue;
        }
        modals += found;

        let closers = text
            .lines()
            .filter(|l| l.trim().starts_with("CloseX {"))
            .count();

        if closers < found {
            failures.push(format!(
                "{name} declares {found} modal(s) but only {closers} CloseX.\n    \
                 A Popup or Dialog covers the window, so it needs a close control \
                 in its top-right corner - `CloseX {{ onClicked: <id>.close() }}`. \
                 Escape works but cannot be seen. If this one genuinely must not \
                 have one, add it to EXEMPT in this file with the reason."
            ));
        }
    }

    assert!(modals > 0, "matched no modals - the scanner is broken");
    assert!(
        failures.is_empty(),
        "{} file(s) have a modal with no way out:\n\n{}",
        failures.len(),
        failures.join("\n\n")
    );
}

/// The same guard the info-button rule has: an exemption without a reason is
/// a silenced test.
#[test]
fn every_modal_exemption_is_argued() {
    for (key, reason) in EXEMPT {
        assert!(
            reason.len() > 60,
            "{key}: exemption reason is {} chars - say why this modal needs no \
             visible way out",
            reason.len()
        );
    }
}

/// The close control itself has to exist, or every file would pass by
/// declaring no modals and the rule would quietly mean nothing.
#[test]
fn the_close_control_exists() {
    let path = qml_dir().join("CloseX.qml");
    let text = fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("{} is the control the rule names: {e}", path.display()));
    assert!(
        text.contains("Button"),
        "CloseX must be a button - something clickable is the entire point"
    );
}
