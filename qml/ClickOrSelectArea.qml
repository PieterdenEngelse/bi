import QtQuick

// Click to act, drag to select - for a tile that is both a control and text
// worth copying.
//
// Two separate handlers cannot do this. A TapHandler keeps only a passive
// grab, so the moment the text under it takes the exclusive grab on press the
// tap is cancelled: the tile either selected or acted, and in one build it
// stopped acting altogether. This owns the press instead and decides from how
// far the pointer moved - under the threshold a click, past it a selection fed
// to the text item through positionAt() and moveCursorSelection().
//
// preventStealing is what keeps that drag from being reinterpreted as a page
// scroll, the same job SelectableText does for text pressed directly.
//
// What it costs: double-click-to-select-a-word inside such a tile, because the
// text no longer sees the press itself. Whatever uses this is the control, and
// explains the gesture in its own info button - this file cannot know what the
// click does.
MouseArea {
    id: root

    /// The text whose selection this drives. A TextEdit-alike: it needs
    /// positionAt(), moveCursorSelection(), cursorPosition, deselect(), and
    /// - for copy-on-select below - selectedText and copy().
    /// Typed `var` so those lookups are not checked against plain Item.
    property var textItem: null

    /// Emitted for a press that never became a drag.
    signal activated()

    readonly property bool hovered: containsMouse

    property real pressX: 0
    property real pressY: 0
    property bool dragging: false
    /// Pixels of travel, |dx|+|dy|, before a press counts as a selection
    /// rather than a click. Qt's own startDragDistance is about 10 and this
    /// sum is stricter than its radius, so 6 lost clicks to ordinary hand
    /// wobble - the release check below is the real safeguard.
    readonly property int dragThreshold: 10

    hoverEnabled: true
    preventStealing: true
    cursorShape: Qt.PointingHandCursor

    // Clamped into the text's own box, because the hit area is allowed to be
    // BIGGER than the glyphs - a one-line value in a toolbar is 14px tall,
    // which is not a drag target.
    //
    // positionAt() does not clamp for you: measured in an offscreen harness,
    // a press 2px above the text returns a position that selects nothing at
    // all. Without this, enlarging a hit area is worse than leaving it small
    // - the press registers, the drag sets `dragging`, the selection stays
    // empty, and the release then falls through to activated(), so trying to
    // drag the build stamp would open the About panel every time.
    function positionIn(mx, my) {
        var p = mapToItem(root.textItem, mx, my)
        var x = Math.max(0, Math.min(root.textItem.width - 1, p.x))
        var y = Math.max(0, Math.min(root.textItem.height - 1, p.y))
        return root.textItem.positionAt(x, y)
    }

    onPressed: (m) => {
        root.pressX = m.x
        root.pressY = m.y
        root.dragging = false
        if (!root.textItem)
            return
        root.textItem.forceActiveFocus()
        root.textItem.cursorPosition = root.positionIn(m.x, m.y)
        root.textItem.deselect()
    }

    onPositionChanged: (m) => {
        if (!root.pressed || !root.textItem)
            return
        if (!root.dragging
            && Math.abs(m.x - root.pressX) + Math.abs(m.y - root.pressY)
               < root.dragThreshold)
            return
        root.dragging = true
        root.textItem.moveCursorSelection(root.positionIn(m.x, m.y))
    }

    // A drag that selected something is final on release, so that is where
    // it goes on the clipboard. The text item cannot do this for itself here:
    // it never sees the press, so its own mouse handling never runs - which
    // is also why these readings fill no primary selection.
    //
    // Guarded on a non-empty selection, so the click path below cannot wipe
    // the clipboard. copy() is TextEdit's own and works on a read-only one.
    onReleased: {
        if (root.dragging
            && root.textItem
            && root.textItem.selectedText.length > 0)
            root.textItem.copy()
    }

    // Decided on release, not on movement: a drag that selected nothing was
    // a click with a shaky hand, and swallowing it means a card that does not
    // open for no visible reason.
    onClicked: {
        if (!root.dragging
            || !root.textItem
            || root.textItem.selectedText.length === 0)
            root.activated()
    }
}
