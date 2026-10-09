import QtQuick
import QtQuick.Controls

// The main vehicle for explaining things, after `rn`'s InfoButton.
//
// A **panel**, not a tooltip: there is room for real prose, and the three
// questions worth answering are what it is, why it matters, and what a wrong
// value looks like. A `title=` style hover hint cannot carry that, and the
// explanation is the product rather than decoration.
//
// Default to adding one. If someone could plausibly ask "what is this?",
// "where did that number come from?" or "what happens if it is wrong?", the
// stat or control gets a button. Err towards too many.
Item {
    id: root

    property string title: ""
    property string what: ""
    property string why: ""
    property string ifWrong: ""

    // Nothing to say means no button, rather than an empty panel.
    readonly property bool hasContent: what !== "" || why !== "" || ifWrong !== ""

    implicitWidth: 16
    implicitHeight: 16
    visible: hasContent

    Rectangle {
        id: dot
        anchors.fill: parent
        radius: width / 2
        color: hover.hovered ? palette.highlight : "transparent"
        border.color: hover.hovered ? palette.highlight : palette.mid
        border.width: 1

        Label {
            anchors.centerIn: parent
            text: "i"
            font.pixelSize: 10
            font.bold: true
            font.family: "serif"
            color: hover.hovered ? palette.highlightedText : palette.text
            opacity: hover.hovered ? 1.0 : 0.55
        }

        // MouseArea, not TapHandler + HoverHandler: TapHandler ignores
        // synthetic clicks (xdotool, and anything else driving the app
        // programmatically), which makes the UI untestable without a human.
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.open()
            property bool hovered: containsMouse
        }
    }

    Popup {
        id: panel
        // Parented to the overlay so the panel is never clipped by the
        // card it belongs to.
        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.min(460, parent.width - 60)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 16

        contentItem: Column {
            spacing: 12

            Label {
                width: parent.width
                text: root.title
                font.bold: true
                font.pixelSize: 15
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: [
                    { heading: "What it is",      body: root.what },
                    { heading: "Why it matters",  body: root.why },
                    { heading: "If it looks wrong", body: root.ifWrong }
                ]

                Column {
                    width: parent.width
                    spacing: 3
                    visible: modelData.body !== ""

                    Label {
                        text: modelData.heading
                        font.pixelSize: 10
                        font.bold: true
                        opacity: 0.55
                    }
                    Label {
                        width: parent.width
                        text: modelData.body
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        lineHeight: 1.25
                    }
                }
            }

            Button {
                anchors.right: parent.right
                text: "Close"
                onClicked: panel.close()
            }
        }
    }
}
