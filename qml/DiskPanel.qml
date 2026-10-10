import QtQuick
import QtQuick.Controls

Panel {
    id: root

    Style { id: style }

    readonly property real usedPct: value ? value.used_fraction * 100 : 0
    readonly property real availGb: value ? value.avail_bytes / 1073741824 : 0
    readonly property real totalGb: value ? value.total_bytes / 1073741824 : 0

    Column {
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
                Behavior on width { NumberAnimation { duration: 300 } }
            }

            Label {
                anchors.centerIn: parent
                text: root.value ? root.usedPct.toFixed(1) + "% used" : "no data"
                font.pixelSize: 12
            }
        }

        StatRow {
            label: "free"
            value: root.value ? root.availGb.toFixed(1) + " GB of " + root.totalGb.toFixed(0) : "—"
            panel: root
            statKey: "avail_bytes"
        }
        StatRow {
            label: "used"
            value: root.value ? root.usedPct.toFixed(1) + "%" : "—"
            panel: root
            statKey: "used_fraction"
        }
        StatRow {
            label: "filesystem"
            value: root.value ? root.value.path : "—"
            panel: root
            statKey: "path"
        }

        Label {
            width: parent.width
            visible: root.usedPct > 85
            text: "Old generations are the usual cause. See Suggested actions."
            font.pixelSize: 11
            opacity: 0.7
            wrapMode: Text.WordWrap
        }
    }
}
