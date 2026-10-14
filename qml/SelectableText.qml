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

    /// The nearest enclosing Flickable, or null when there is none above us.
    /// Duck-typed rather than matched on type: ScrollView scrolls with an
    /// internal Flickable, and the parent chain runs through its content item.
    property Item scroller: null

    Component.onCompleted: {
        for (var p = root.parent; p; p = p.parent) {
            if (p.contentY !== undefined && p.flicking !== undefined) {
                root.scroller = p
                break
            }
        }
    }

    // A passive grab only - PointHandler never takes the exclusive grab, so
    // the TextEdit still receives the moves that extend a selection.
    PointHandler { id: press }

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
