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
// The rows are ONE rich-text item, and getting there cost three wrong turns
// worth recording, because each one is a thing Qt will do to you again:
//
//   1. A Repeater of per-cell items. Separate text items cannot share a
//      selection, so only one value could ever be highlighted - there was no
//      drag that took a whole row, let alone the section.
//   2. One item holding a rich-text <table>. Qt snaps a selection to WHOLE
//      CELLS as soon as the drag leaves the cell it started in
//      (QTextCursor::hasComplexSelection). Rows are 13px tall, so a drag that
//      wandered a few pixels lit up every cell it had crossed: the tile
//      flashed solid and a single store path could not be lifted out.
//   3. A per-field grid plus a Select all button. Precise, but it put the
//      obvious gesture behind a control you had to find first.
//
// So: one item, rich text, no table. Blocks select by character, which is what
// a drag is supposed to do - anywhere in the tile, across as many rows as you
// like, and Ctrl+A for all of it. Columns are aligned with &nbsp; padding in a
// monospace font rather than cells; HTML collapses ordinary runs of spaces,
// which &nbsp; does not. Per-span colour survives, so the provenance column
// stays muted.
//
// What it costs: a value longer than its column pushes the rest of that line
// right, and a store path wraps mid-path rather than being clipped. Both were
// true of the table as well.
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

    function pad(n) {
        var s = ""
        for (var i = 0; i < n; i++)
            s += "&nbsp;"
        return s
    }

    /// Width of the label column, in characters: the longest label plus two.
    /// Monospace, so character count is the column.
    readonly property int labelWidth: {
        var w = 0
        for (var i = 0; i < rows.length; i++)
            w = Math.max(w, String(rows[i].label).length)
        return w + 2
    }

    function rowsHtml() {
        // The title is the first line of the same text item, not a heading
        // above it. A drag naturally starts at the top-left of a tile - on
        // the title - and a drag that begins in one item can only select
        // inside that item, so starting there used to get you the title and
        // nothing else. Sans-serif and larger, so it still reads as a
        // heading inside an otherwise monospace block.
        var h = "<div><span style='font-family:sans-serif; font-size:14px; "
              + "font-weight:bold; color:" + style.textStrong + "'>"
              + body.esc(root.title) + "</span></div>"
        for (var i = 0; i < root.rows.length; i++) {
            var r = root.rows[i]
            var label = String(r.label)
            h += "<div><span style='color:" + style.textMuted + "'>"
               + body.esc(label) + root.pad(root.labelWidth - label.length)
               + "</span><span style='color:" + style.text + "'>"
               + body.esc(r.value) + "</span></div>"
            // The provenance on its own indented line. Beside the value it
            // was the first thing a long store path pushed off the tile.
            if (r.source)
                h += "<div>" + root.pad(root.labelWidth)
                   + "<span style='color:" + style.textMuted + "'>&#8627; "
                   + body.esc(r.source) + "</span></div>"
        }
        return h
    }

    /// The same rows as plain text, for the clipboard. Tabs rather than
    /// padding: this is going into an editor or a terminal, not back into a
    /// fixed-width column.
    function sectionText() {
        var out = root.title + "\n"
        for (var i = 0; i < root.rows.length; i++) {
            var r = root.rows[i]
            out += r.label + "\t" + r.value + "\t" + r.source + "\n"
        }
        return out
    }

    Clipboard { id: clip }

    // Ctrl+Shift+C while the pointer is over this section, the same gesture
    // every panel answers to. It hands back tab-separated text rather than
    // what is on screen: the columns here line up because the labels are
    // padded with non-breaking spaces, and those are not what you want in a
    // paste.
    HoverHandler { id: sectionHover }
    Shortcut {
        sequences: [ "Ctrl+Shift+C" ]
        enabled: sectionHover.hovered
        onActivated: clip.put(root.sectionText())
    }

    Column {
        id: col
        x: 14
        y: 12
        width: parent.width - 28
        spacing: 6


        // Monospace because the columns are padded, not laid out: a
        // proportional font makes &nbsp; padding line up to nothing.
        SelectableText {
            id: body
            width: parent.width
            text: root.rowsHtml()
            textFormat: TextEdit.RichText
            font.family: "monospace"
            // The floor, for the same reason the panels use it:
            // screen-scale.nix downscales a 120% framebuffer. See
            // `fontBody` in Style.qml, which is now where that rule lives.
            font.pixelSize: style.fontBody
            color: style.text
            // Word boundaries first, mid-word only when a run has none -
            // which is every store path.
            wrapMode: TextEdit.Wrap
        }
    }
}
