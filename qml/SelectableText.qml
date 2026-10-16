import QtQuick

// Text that carries content rather than chrome: drag across it and you get
// exactly what you dragged.
//
// `selectByMouse` is almost all a TextEdit needs. The part it cannot do by
// itself is survive the page it sits on: every page is a ScrollView, and a
// Flickable decides partway through a downward drag that the gesture was a
// scroll, takes the grab, and throws the half-made selection away. While a
// button is held on this text the enclosing Flickable stops being
// interactive, so the drag stays here and the selection is the dragged range.
//
// This replaced a `TapHandler { onTapped: selectAll() }` on every selectable
// text, which worked around the same stolen-drag problem from the other
// side - at the cost of making a partial selection impossible, since the
// press that started one also replaced it with the whole block. Selecting
// everything is still a gesture: Ctrl+A, or triple-click where the text sees
// the press itself.
//
// That Ctrl+A is a window shortcut in Main.qml, not this TextEdit's own key
// handling. It is read-only, which leaves selectByKeyboard false, and in that
// state the key never arrived - so this line described a gesture that did
// nothing for as long as it has been here.
TextEdit {
    id: root

    readOnly: true
    selectByMouse: true

    // Selecting copies, to BOTH selections.
    //
    // Qt fills the X11 primary selection from its own mouse handling, so a
    // middle-click has always pasted a dragged value. The ordinary clipboard -
    // the one Ctrl+V and every other application's paste reads - is filled
    // here, on release.
    //
    // This reverses an earlier decision to leave the clipboard alone, whose
    // argument was that dragging across a value merely to READ it should not
    // wipe what you had copied. That cost is real and was accepted
    // deliberately: copy-on-select is the wanted behaviour. The guard in
    // copySelection() limits the cost to drags - a click selects nothing and
    // leaves the clipboard untouched.
    //
    // TextEdit defaults its colour to BLACK, not to the palette - a Label
    // converted to one without setting `color` goes invisible on this dark
    // scheme. Default to the palette and let call sites override.
    color: palette.text

    /// Puts the current selection on the ordinary clipboard.
    ///
    /// `copy()` works on a read-only TextEdit - Clipboard.qml is built on
    /// exactly that trick - so this needs neither selectByKeyboard nor the
    /// blinking cursor it would put in every value tile.
    ///
    /// Guarded on a non-empty selection, so a plain click never clears what
    /// you had copied.
    function copySelection() {
        if (root.selectedText.length > 0)
            root.copy()
    }

    /// Escapes engine-supplied text for use inside a RichText body. Values
    /// land inside markup, so they are escaped rather than trusted: a target
    /// list containing `<` would otherwise disappear into a tag.
    function esc(s) {
        return String(s).replace(/&/g, "&amp;")
                        .replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    /// The nearest enclosing Flickable, or null when there is none above us.
    /// Duck-typed rather than matched on type: ScrollView scrolls with an
    /// internal Flickable, and the parent chain runs through its content
    /// item. qmllint flags the two probes below as members missing from
    /// Item, which is the point of a probe: QML resolves them at runtime,
    /// and a Flickable answers while a plain Item does not.
    property var scroller: null

    function findScroller() {
        for (var p = root.parent; p; p = p.parent) {
            // qmllint disable missing-property
            // The probe the comment above describes: a Flickable answers,
            // a plain Item does not, and asking is how we find out.
            if (p.contentY !== undefined && p.flicking !== undefined)
                return p
            // qmllint enable missing-property
        }
        return null
    }

    // Resolved at PRESS time, not at completion.
    //
    // Component.onCompleted is too early for a text inside a nested
    // component: when this item completes, its own parents exist but the
    // component that contains it has not been parented yet, so the walk
    // reaches a null parent and gives up. `scroller` then stayed null
    // forever, the guard below never engaged, and a downward drag across
    // rows was free to be reinterpreted as a scroll - selecting one value
    // worked, selecting several never did. By the time a press arrives the
    // tree is fully parented, so the same walk succeeds.
    PointHandler {
        id: press
        // NO margin here, however tempting. `margin: 2000` was added to keep
        // this handler active while a drag wandered outside the item, and it
        // broke mouse input across the whole window: margin widens the area
        // in which the handler claims a point, so every selectable text in
        // the scene claimed every press within 2000px of itself - including
        // texts that render nothing, like the hidden "waiting for the engine"
        // line. Whichever was frontmost in paint order swallowed the press,
        // so subject cards stopped opening and panel rows stopped selecting.
        // Found with an offscreen qmltestrunner harness after three wrong
        // theories; the margin is not worth a fourth.
        onActiveChanged: {
            if (press.active) {
                if (root.scroller === null)
                    root.scroller = root.findScroller()
            } else {
                // Released: the selection is whatever it ended up being, so
                // copy it. On release rather than on selectedTextChanged,
                // which fires on every pixel of a drag.
                root.copySelection()
            }
        }
    }

    // Declarative, so the scroller's own `interactive` binding or value comes
    // back on release rather than being overwritten with a guessed `true`.
    Binding {
        target: root.scroller
        property: "interactive"
        value: false
        when: root.scroller !== null && press.active
        restoreMode: Binding.RestoreBindingOrValue
    }
}
