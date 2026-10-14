import QtQuick
import QtQuick.Controls

Panel {
    id: root

    Style { id: style }

    readonly property int count: value ? value.count : 0
    readonly property var unavailable: value && value.unavailable_scopes
                                       ? value.unavailable_scopes : []

    // So the header's Copy hands back the units themselves, not just the
    // "3 failed" headline. Tab-separated, like every other copy here.
    extraText: {
        var units = root.value ? root.value.units : []
        var out = ""
        for (var i = 0; i < units.length; i++)
            out += units[i].unit + "\t" + units[i].scope + "\t"
                 + units[i].description + "\n"
        return out
    }

    Column {
        width: parent.width
        height: parent.height
        spacing: 4

        // "Nothing failed" and "could not look" must never render the same,
        // so the blind scopes get their own row rather than being folded
        // into the count.
        StatBlock {
            panel: root
            rows: [
                { label: "failed",
                  value: root.value ? String(root.count) : "—",
                  statKey: "count" },
                { label: "scopes unreadable",
                  value: root.unavailable.length === 0
                         ? "none" : root.unavailable.join(", "),
                  statKey: "unavailable_scopes" }
            ]
        }

        ListView {
            width: parent.width
            height: parent.height - y - 4
            clip: true
            model: root.value ? root.value.units : []
            spacing: 3

            delegate: Column {
                width: ListView.view.width
                // The unit name goes straight into a systemctl command, so
                // it is selectable and wraps rather than being cut off. The
                // list is a Flickable: SelectableText stops it claiming the
                // drag, so selecting here does not scroll the list instead.
                SelectableText {
                    text: modelData.unit + "  (" + modelData.scope + ")"
                    font.pixelSize: 12
                    color: style.badDot
                    wrapMode: TextEdit.Wrap
                    width: parent.width
                }
                SelectableText {
                    text: modelData.description
                    font.pixelSize: 10
                    wrapMode: TextEdit.Wrap
                    width: parent.width
                }
            }

            Label {
                anchors.centerIn: parent
                visible: root.value && root.count === 0 && root.unavailable.length === 0
                text: "✓"
                font.pixelSize: 26
                // Kept faint where body text no longer is: this is a
                // watermark behind an empty list, not something to read.
                opacity: 0.25
            }
        }
    }
}
