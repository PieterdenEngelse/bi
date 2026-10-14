import QtQuick
import QtQuick.Controls

// One subject's block on the Config page: a title and rows of
// label / value / where-it-comes-from.
//
// The third column is the point. A value with no provenance tells you what is
// true but not what to edit, which on a declarative system is most of the
// question.
//
// ---------------------------------------------------------------------------
// The whole section is **one** TextEdit holding a rich-text table, not a
// Repeater of per-cell items. Separate items cannot share a selection, so the
// per-row version allowed exactly one value to be highlighted at a time -
// there was no way to drag across three rows and copy them.
//
// What that costs: a store path has no spaces, so it can only wrap mid-path
// rather than being clipped with an ellipsis, and a row holding one is two
// lines tall. That is the trade for being able to select more than one line.
Rectangle {
    id: root

    property string title: ""
    /// [{ label, value, source }]
    property var rows: []

    implicitHeight: col.implicitHeight + 24
    radius: 8
    color: palette.base
    border.color: palette.mid

    Style { id: style }

    // Values come from the engine and land inside markup, so they are escaped
    // here rather than trusted. A target list containing `<` would otherwise
    // disappear into a tag.
    function esc(s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    function sectionHtml() {
        var h = "<div style='font-size:14px; font-weight:bold; color:"
              + style.textStrong + "'>" + root.esc(root.title) + "</div>"
              + "<table width='100%' cellspacing='0' cellpadding='3'>"
        for (var i = 0; i < root.rows.length; i++) {
            var r = root.rows[i]
            h += "<tr>"
               + "<td width='26%'><span style='font-size:11px; color:" + style.textMuted
               + "'>" + root.esc(r.label) + "</span></td>"
               + "<td width='42%'><span style='font-size:11px; font-family:monospace; color:"
               + style.text + "'>" + root.esc(r.value) + "</span></td>"
               + "<td width='26%'><span style='font-size:10px; color:" + style.textMuted
               + "'>" + root.esc(r.source) + "</span></td>"
               + "</tr>"
        }
        return h + "</table>"
    }

    Column {
        id: col
        x: 14
        y: 12
        width: parent.width - 28

        SelectableText {
            id: body
            width: parent.width
            text: root.sectionHtml()
            textFormat: TextEdit.RichText
            // Word boundaries first, mid-word only when a run has none - which
            // is every store path.
            wrapMode: TextEdit.Wrap
            color: style.text

            // Secondary text is #9ca3af and no darker, per Style.qml. The
            // per-cell version dimmed #d1d5db to 0.45 and 0.65 opacity, which
            // lands well under that floor; rich text has no per-span opacity
            // anyway, so both columns now use the named colour.

            // Drag selection is precise here because SelectableText stops the
            // page scroller from claiming the drag halfway through; see there.
        }
    }
}
