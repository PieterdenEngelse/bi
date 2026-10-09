import QtQuick
import QtQuick.Controls

// One subject's block on the Config page: a title and rows of
// label / value / where-it-comes-from.
//
// The third column is the point. A value with no provenance tells you what is
// true but not what to edit, which on a declarative system is most of the
// question.
Rectangle {
    id: root

    property string title: ""
    /// [{ label, value, source }]
    property var rows: []

    implicitHeight: col.implicitHeight + 24
    radius: 8
    color: palette.base
    border.color: palette.mid

    Column {
        id: col
        x: 14
        y: 12
        width: parent.width - 28
        spacing: 7

        Label {
            text: root.title
            font.bold: true
            font.pixelSize: 14
        }

        Repeater {
            model: root.rows

            Row {
                width: parent.width
                spacing: 10

                Label {
                    width: parent.width * 0.26
                    text: modelData.label
                    font.pixelSize: 11
                    opacity: 0.65
                    elide: Text.ElideRight
                }

                // Selectable: a store path or a target list is something you
                // will want to paste somewhere.
                TextEdit {
                    width: parent.width * 0.42
                    text: modelData.value
                    readOnly: true
                    selectByMouse: true
                    font.pixelSize: 11
                    font.family: "monospace"
                    color: palette.text
                    wrapMode: TextEdit.NoWrap
                    clip: true
                }

                Label {
                    width: parent.width * 0.26
                    text: modelData.source
                    font.pixelSize: 10
                    opacity: 0.45
                    elide: Text.ElideLeft
                }
            }
        }
    }
}
