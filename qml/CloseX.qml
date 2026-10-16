import QtQuick
import QtQuick.Controls

// The close affordance every modal carries, in its top-right corner.
//
// One implementation for all of them, not because the markup is long but
// because "every modal has a visible way out" is a rule, and a rule with
// three copies is three places for it to drift. `qml_modals.rs` counts these
// against the Popup and Dialog declarations in the same file.
//
// Escape and a click outside already close these panels. Neither is visible.
// A modal that covers the window with no exit you can SEE reads as a hang,
// and "press Escape" is only obvious to someone who already knows - which,
// in an app whose whole purpose is explaining this machine to someone
// learning it, is the wrong assumption to build a dialog on.
Button {
    id: root

    flat: true

    // MULTIPLICATION X (U+2715), not a lowercase letter x and not one of the
    // heavy ballot crosses: it is the glyph that renders as a symmetric cross
    // at text weight in the fonts this ships with, and it is not a letter
    // that a screen reader or a text search would treat as a word.
    text: "✕"

    // Square and small enough to read as chrome rather than as one of the
    // panel's own controls, but still a comfortable pointer target.
    implicitWidth: 28
    implicitHeight: 28
    padding: 0

    // The cursor change arrives before the glyph is read, which is most of
    // what makes a bare symbol feel like a button at all.
    hoverEnabled: true

    Accessible.name: "Close"
    Accessible.description: "Closes this panel. Escape does the same."

    ToolTip.text: "Close  (Esc)"
    ToolTip.visible: root.hovered
    ToolTip.delay: 400
}
