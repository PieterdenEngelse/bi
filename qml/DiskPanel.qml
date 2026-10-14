import QtQuick
import QtQuick.Controls

Panel {
    id: root

    Style { id: style }

    readonly property real usedPct: value ? value.used_fraction * 100 : 0
    readonly property real availGb: value ? value.avail_bytes / 1073741824 : 0
    readonly property real totalGb: value ? value.total_bytes / 1073741824 : 0

    // Grows by one line when the >85% hint appears, so a constant cannot be
    // right in both states.
    contentHeight: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: 8

        Item { width: 1; height: 2 }

        Rectangle {
            width: parent.width
            height: 22
            radius: 4
            color: palette.alternateBase
            border.color: palette.mid

            Rectangle {
                x: 1; y: 1
                height: parent.height - 2
                width: Math.max(0, Math.min(1, root.usedPct / 100)) * (parent.width - 2)
                radius: 3
                color: root.stateColors[root.state_] || style.unknownDot
                opacity: 0.55
                // No width animation. Main polls every 2s and assigns a fresh
                // array to `panels`; SubjectPage's `panelsFor()` returns a new
                // array again, so the Repeater tears down and rebuilds every
                // delegate on each poll. The bar is recreated with no value,
                // then animates 0 -> 65% as the summary lands - a 300ms sweep
                // twice a minute, which reads as flicker. This is the only
                // panel with an animated dimension, which is why it was the
                // only one that flickered. Disk usage moves by fractions of a
                // percent between polls; there is nothing for an animation to
                // smooth.
            }

            SelectableText {
                anchors.centerIn: parent
                text: root.value ? root.usedPct.toFixed(1) + "% used" : "no data"
                font.pixelSize: 12
            }
        }

        StatBlock {
            panel: root
            rows: [
                { label: "free",
                  value: root.value ? root.availGb.toFixed(1) + " GB of "
                                      + root.totalGb.toFixed(0) : "—",
                  statKey: "avail_bytes" },
                { label: "used",
                  value: root.value ? root.usedPct.toFixed(1) + "%" : "—",
                  statKey: "used_fraction" },
                { label: "filesystem",
                  value: root.value ? root.value.path : "—",
                  statKey: "path" }
            ]
        }

        SelectableText {
            width: parent.width
            visible: root.usedPct > 85
            text: "Old generations are the usual cause. See Suggested actions."
            font.pixelSize: 11
            wrapMode: TextEdit.Wrap
        }
    }
}
