import QtQuick
import QtQuick.Controls

Panel {
    id: root

    Style { id: style }

    readonly property int count: value ? value.count : 0
    readonly property var unavailable: value && value.unavailable_scopes
                                       ? value.unavailable_scopes : []

    Column {
        width: parent.width
        height: parent.height
        spacing: 4

        StatRow {
            label: "failed"
            value: root.value ? String(root.count) : "—"
            panel: root
            statKey: "count"
        }
        StatRow {
            // "Nothing failed" and "could not look" must never render the
            // same, so the blind scopes get their own row rather than being
            // folded into the count.
            label: "scopes unreadable"
            value: root.unavailable.length === 0 ? "none" : root.unavailable.join(", ")
            panel: root
            statKey: "unavailable_scopes"
        }

        ListView {
            width: parent.width
            height: parent.height - y - 4
            clip: true
            model: root.value ? root.value.units : []
            spacing: 3

            delegate: Column {
                width: ListView.view.width
                Label {
                    text: modelData.unit + "  (" + modelData.scope + ")"
                    font.pixelSize: 12
                    color: style.badDot
                    elide: Text.ElideRight
                    width: parent.width
                }
                Label {
                    text: modelData.description
                    font.pixelSize: 10
                    opacity: 0.65
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            Label {
                anchors.centerIn: parent
                visible: root.value && root.count === 0 && root.unavailable.length === 0
                text: "✓"
                font.pixelSize: 26
                opacity: 0.25
            }
        }
    }
}
