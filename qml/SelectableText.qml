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
// everything is still a gesture: Ctrl+A, or triple-click.
TextEdit {
    id: root

    readOnly: true
    selectByMouse: true
    // Selecting is already copying on this desktop: Qt puts the dragged text
    // on the X11 primary selection, so a middle-click pastes it without
    // Ctrl+C. Verified against the running window - the disk panel's "free"
    // row turned up in PRIMARY after a drag, with the clipboard still empty.
    // Nothing here implements it, and nothing should: writing selections to
    // the ordinary clipboard instead would wipe whatever you had copied every
    // time you dragged across a value to read it.
    // TextEdit defaults its colour to BLACK, not to the palette - a Label
    // converted to one without setting `color` goes invisible on this dark
    // scheme. Default to the palette and let call sites override.
    color: palette.text

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
            if (p.contentY !== undefined && p.flicking !== undefined)
                return p
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
            if (press.active && root.scroller === null)
                root.scroller = root.findScroller()
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
