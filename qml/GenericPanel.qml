import QtQuick
import QtQuick.Controls

// Renders any panel from its engine-supplied metadata alone.
//
// Used for panels without a bespoke visual, and as the fallback when the
// engine grows one the UI has never heard of - a new panel should appear,
// readable and explained, without a UI release. Bespoke panels exist where a
// picture beats a list; everything else is better served by honest key/value.
Panel {
    id: root

    Style { id: style }

    // Size to the stat count rather than the Panel default, so a long list is
    // not silently clipped at the bottom of the card.
    // Content-driven, via Panel's own mechanism: the readings are one text
    // block now, and a block whose values wrap is taller than stat-count
    // arithmetic can predict.
    contentHeight: col.implicitHeight

    // The formatting itself lives in Panel, so the header's Copy and these
    // rows cannot disagree about what a value looks like.
    function render(v) {
        return root.renderValue(v)
    }

    // A plain Column, not a ScrollView. The panel sizes to its stat count
    // above, so there is nothing to scroll - and ScrollView wraps its content
    // in a Flickable that grabs the press, which left every per-stat info
    // button unclickable. The header button worked only because it sits
    // outside the scrolled area.
    Column {
        id: col
        anchors.fill: parent
        spacing: 3

        // Driven by the engine's stat list rather than the value's own keys:
        // the stats carry a documented order and are guaranteed by test to
        // cover every key emitted.
        StatBlock {
            panel: root
            rows: {
                var stats = root.summary && root.summary.stats
                          ? root.summary.stats : []
                var out = []
                for (var i = 0; i < stats.length; i++)
                    out.push({ label: stats[i].key,
                               value: root.render(root.value
                                                  ? root.value[stats[i].key]
                                                  : null),
                               statKey: stats[i].key })
                return out
            }
        }

        // A failed probe is the thing you most want to paste somewhere else.
        SelectableText {
            visible: root.summary && root.summary.error
            width: parent.width
            text: root.summary ? "error: " + root.summary.error : ""
            color: style.warnDot
            font.pixelSize: style.fontBody
            wrapMode: TextEdit.Wrap
        }
    }
}
