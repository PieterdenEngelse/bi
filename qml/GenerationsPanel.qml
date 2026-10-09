import QtQuick
import QtQuick.Controls

Panel {
    id: root

    function ago(ms) {
        var mins = Math.floor((Date.now() - ms) / 60000)
        if (mins < 60) return mins + "m ago"
        var hours = Math.floor(mins / 60)
        if (hours < 24) return hours + "h ago"
        return Math.floor(hours / 24) + "d ago"
    }

    Column {
        width: parent.width
        height: parent.height
        spacing: 4

        StatRow {
            label: "reboot pending"
            value: root.value ? (root.value.reboot_needed ? "yes" : "no") : "—"
            panel: root
            statKey: "reboot_needed"
        }

        ListView {
            width: parent.width
            height: parent.height - y - 4
            clip: true
            model: root.value ? root.value.generations : []
            spacing: 2

            delegate: Row {
                width: ListView.view.width
                spacing: 8

                Label {
                    width: 46
                    text: "#" + modelData.number
                    font.pixelSize: 12
                    font.bold: modelData.current
                    opacity: modelData.current ? 1.0 : 0.6
                }
                Label {
                    text: root.ago(modelData.at)
                    font.pixelSize: 12
                    opacity: modelData.current ? 0.8 : 0.45
                }
                Label {
                    visible: modelData.current
                    text: "· current"
                    font.pixelSize: 12
                    opacity: 0.8
                }
            }
        }
    }
}
