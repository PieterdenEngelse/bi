import QtQuick

// The app's one way onto the clipboard.
//
// QML has no clipboard API at all. The trick is an off-screen TextEdit:
// filling it, selecting it and calling copy() puts text on the clipboard, and
// it works on both desktop and wasm - in the browser a key press or a button
// press is the user gesture the clipboard permission requires, and both of
// ours are exactly that.
//
// It lives here because three panels had grown their own identical copy of
// the same eight lines. One implementation means one place to fix when the
// wasm clipboard rules change again.
Item {
    id: root

    visible: false

    function put(text) {
        sink.text = text
        sink.selectAll()
        sink.copy()
        sink.deselect()
    }

    TextEdit {
        id: sink
        visible: false
        readOnly: true
    }
}
