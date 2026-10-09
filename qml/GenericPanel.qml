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

    // Size to the stat count rather than the Panel default, so a long list is
    // not silently clipped at the bottom of the card.
    implicitHeight: 62 + (summary && summary.stats ? summary.stats.length : 0) * 21

    function render(v) {
        if (v === null || v === undefined)
            return "—"
        // Not Array.isArray: a JSON array reaching QML through a `var`
        // property arrives as a QVariantList, which fails that check and
        // would fall through to JSON.stringify. Duck-type instead.
        if (typeof v === "object" && typeof v.length === "number")
            return v.length === 0 ? "none" : Array.prototype.join.call(v, ", ")
        if (typeof v === "boolean")
            return v ? "yes" : "no"
        if (typeof v === "object")
            return JSON.stringify(v)
        return String(v)
    }

    // A plain Column, not a ScrollView. The panel sizes to its stat count
    // above, so there is nothing to scroll - and ScrollView wraps its content
    // in a Flickable that grabs the press, which left every per-stat info
    // button unclickable. The header button worked only because it sits
    // outside the scrolled area.
    Column {
        anchors.fill: parent
        spacing: 3

        // Driven by the engine's stat list rather than the value's own keys:
        // the stats carry a documented order and are guaranteed by test to
        // cover every key emitted.
        Repeater {
            model: root.summary ? root.summary.stats : []

            StatRow {
                label: modelData.key
                value: root.render(root.value ? root.value[modelData.key] : null)
                panel: root
                statKey: modelData.key
            }
        }

        Label {
            visible: root.summary && root.summary.error
            width: parent.width
            text: root.summary ? "error: " + root.summary.error : ""
            color: "#ff9800"
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
    }
}
