import QtQuick
import QtQuick.Controls

// One labelled value with its info button.
//
// The button is always the row's last child at full width, which is what
// makes the buttons line up in a single column however long the values beside
// them are. A button that tracked its own text would make a panel look like
// scattered punctuation - handled here once, not per panel.
Item {
    id: root

    property string label: ""
    property string value: ""
    /// The owning Panel, used to look up this key's explanation.
    property var panel: null
    /// Key in the panel's stats. Leave empty for a row with no engine info.
    property string statKey: ""

    /// Tint for the value, for rows that are a verdict rather than a reading.
    property color valueColor: palette.text

    /// Set directly when the row is not backed by a panel stat.
    property string what: ""
    property string why: ""
    property string ifWrong: ""

    readonly property var stat: panel && statKey !== "" ? panel.infoFor(statKey) : null

    implicitHeight: Math.max(18, text.implicitHeight)
    width: parent ? parent.width : 0

    Label {
        id: name
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(140, root.width * 0.4)
        text: root.label
        font.pixelSize: 11
        opacity: 0.6
        elide: Text.ElideRight
    }

    Label {
        id: text
        anchors.left: name.right
        anchors.leftMargin: 8
        anchors.right: info.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.value
        color: root.valueColor
        font.pixelSize: 11
        elide: Text.ElideRight
    }

    InfoButton {
        id: info
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        title: root.label
        what: root.stat ? root.stat.what : root.what
        why: root.stat ? root.stat.why : root.why
        ifWrong: root.stat ? root.stat.if_wrong : root.ifWrong
    }
}
