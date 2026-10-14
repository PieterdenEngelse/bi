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

    // The generation list itself, for the header's Copy.
    extraText: {
        var gens = root.value ? root.value.generations : []
        var out = ""
        for (var i = 0; i < gens.length; i++)
            out += "#" + gens[i].number + "\t" + root.ago(gens[i].at)
                 + (gens[i].current ? "\tcurrent" : "") + "\n"
        return out
    }

    Column {
        width: parent.width
        height: parent.height
        spacing: 4

        StatBlock {
            panel: root
            rows: [
                { label: "reboot pending",
                  value: root.value ? (root.value.reboot_needed ? "yes" : "no")
                                    : "—",
                  statKey: "reboot_needed" }
            ]
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

                // A generation number is what you type into a rollback, so
                // it is selectable. The list is a Flickable: SelectableText
                // keeps it from claiming the drag.
                SelectableText {
                    width: 46
                    text: "#" + modelData.number
                    font.pixelSize: 12
                    font.bold: modelData.current
                }
                SelectableText {
                    text: root.ago(modelData.at)
                    font.pixelSize: 12
                }
                SelectableText {
                    visible: modelData.current
                    text: "· current"
                    font.pixelSize: 12
                }
            }
        }
    }
}
