import QtQuick

// A panel's readings as ONE selectable text item, with each reading's info
// button parked beside its own row.
//
// Why one item: separate items cannot share a selection, so a Repeater of
// per-row items meant a drag could never take more than one reading - which
// is the complaint this exists to answer. Why the buttons stay per reading:
// every stat gets its own explanation, and one panel-level info button cannot
// carry a dozen of them.
//
// The buttons find their row with positionToRectangle(), which reports where
// a document position actually landed - so a value that wraps onto a second
// line pushes its own button down with it, instead of a fixed-pitch column
// drifting out of step with the text.
//
// Monospace, because the label column is padded rather than laid out: a
// proportional font makes that padding line up to nothing. Same trade the
// Config page's tiles already make.
//
// One reading per info button, so the LINE PITCH IS THE BUTTON SIZE. At the
// text's natural 14px leading the 24px buttons overlapped into a chain of
// circles down the right edge of every panel - they are positioned from the
// document, so they can only be as far apart as the rows are.
//
// Style.qml's floor, not the 11px this started at: screen-scale.nix
// downscales a 120% framebuffer, so 11px rendered smaller than 11px. That
// rule now lives in Style.qml as `fontBody` rather than in this comment -
// it was stated here and in ConfigSection.qml, both deferring to a
// paragraph Style.qml did not actually have, and was under-run in 54 places
// before anyone counted. These rows are the main thing a panel exists to be
// read from.
Item {
    id: root

    /// The owning Panel, used to look up each key's explanation.
    property var panel: null

    /// [{ label, value, statKey, color, what, why, ifWrong }] - `statKey`
    /// looks the explanation up from the panel; what/why/ifWrong give one
    /// directly, for a row the engine does not describe.
    property var rows: []

    Style { id: style }

    width: parent ? parent.width : 0
    implicitHeight: body.implicitHeight

    /// Reserved for the button column, so no text runs under it.
    readonly property int infoWidth: style.infoSize + 8

    /// Label column width, in characters: the longest label plus two.
    readonly property int labelWidth: {
        var w = 0
        for (var i = 0; i < rows.length; i++)
            w = Math.max(w, String(rows[i].label).length)
        return w + 2
    }

    /// One entry per row, with the label padded to the column width. Only
    /// the markup uses this now - the button positions are read back from
    /// the rendered document instead, see `offsets`.
    readonly property var lines: {
        var out = []
        for (var i = 0; i < rows.length; i++) {
            var label = String(rows[i].label)
            var v = rows[i].value
            out.push({
                label: label,
                value: v === undefined || v === null ? "" : String(v),
                pad: Math.max(1, root.labelWidth - label.length)
            })
        }
        return out
    }

    /// Document position where each row begins, read back from the document
    /// itself rather than predicted.
    ///
    /// Predicting it from label + padding + value lengths looked right and
    /// was not: the row set is rebuilt on every poll, and the bindings do not
    /// settle in one pass, so for a frame these positions were being asked of
    /// the *previous*, shorter document. Qt answered with a wall of
    /// "QTextCursor::setPosition: Position N out of range". getText() returns
    /// the plain text of the document as it stands right now, with paragraphs
    /// separated by U+2029, so splitting that cannot disagree with the
    /// document it came from.
    readonly property var offsets: {
        var len = body.length
        // Read so this re-runs when the markup changes, not only its length.
        var dependency = body.text
        var plain = len > 0 ? body.getText(0, len) : ""
        var out = []
        var pos = 0
        var parts = plain.split("\u2029")
        for (var i = 0; i < parts.length; i++) {
            out.push(pos)
            pos += parts[i].length + 1
        }
        return out
    }

    function nbsp(n) {
        var s = ""
        for (var i = 0; i < n; i++)
            s += "&nbsp;"
        return s
    }

    function rowsHtml() {
        var h = ""
        for (var i = 0; i < root.lines.length; i++) {
            var l = root.lines[i]
            h += "<div style='line-height:" + style.infoSize + "px'>"
               + "<span style='color:" + style.textMuted + "'>"
               + body.esc(l.label) + root.nbsp(l.pad)
               + "</span><span style='color:"
               + (root.rows[i].color ? root.rows[i].color : style.text) + "'>"
               + body.esc(l.value) + "</span></div>"
        }
        return h
    }

    SelectableText {
        id: body
        width: Math.max(0, root.width - root.infoWidth)
        textFormat: TextEdit.RichText
        font.family: "monospace"
        font.pixelSize: style.fontBody
        wrapMode: TextEdit.Wrap
        text: root.rowsHtml()
    }

    // Selection driven by hand, not by the TextEdit's own mouse handling.
    //
    // Native selectByMouse works for a Config tile but not here, and three
    // attempts at finding out why from the outside failed: the rows lay out
    // correctly, nothing covers them, no binding errors, and the guard that
    // stops a page's Flickable claiming the drag is in place and resolved at
    // press time. Rather than a fourth theory, this owns the press -
    // preventStealing means nothing can take it - and drives the same
    // selection the TextEdit would have.
    //
    // Two costs, both real: double-click-to-select-a-word in a panel, and the
    // X11 primary selection, which Qt fills from its own mouse handling and
    // not from a programmatic selection - so middle-click paste works from
    // Config tiles but not from these readings.
    //
    // The ORDINARY clipboard is filled either way: ClickOrSelectArea copies
    // on release just as a directly-pressed text does, so Ctrl+V, Ctrl+C and
    // Ctrl+Shift+C all work here. Only middle-click is lost.
    ClickOrSelectArea {
        anchors.fill: body
        textItem: body
        cursorShape: Qt.IBeamCursor
    }

    Repeater {
        model: root.rows

        InfoButton {
            readonly property var stat: root.panel && modelData.statKey
                                        ? root.panel.infoFor(modelData.statKey)
                                        : null
            x: root.width - width
            // The text and the width are read explicitly so this re-runs when
            // the block relays out: a binding over a function call alone does
            // not notice that the rows moved.
            // A row with no paragraph of its own yet - the document is
            // mid-rebuild - parks on an estimated pitch rather than asking
            // for a position the document does not have. Asking anyway is
            // what produced the "out of range" warnings.
            y: {
                var w = body.width
                var len = body.length
                var o = root.offsets[index]
                if (o === undefined || o > len)
                    return index * 16
                var r = body.positionToRectangle(o)
                return r.y + Math.max(0, (r.height - height) / 2)
            }
            title: modelData.label
            what: stat ? stat.what : (modelData.what ? modelData.what : "")
            why: stat ? stat.why : (modelData.why ? modelData.why : "")
            ifWrong: stat ? stat.if_wrong
                          : (modelData.ifWrong ? modelData.ifWrong : "")
            // Absent on every reading that does not want tabs: the engine
            // skips the field entirely when the slice is empty, so this is
            // undefined far more often than it is a list.
            sections: stat && stat.sections ? stat.sections : []
        }
    }
}
