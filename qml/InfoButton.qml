import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

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
//
// ---------------------------------------------------------------------------
// Writing content for one
//
// Bodies are **rich text**. That buys three things worth using:
//
//   <b>…</b> <i>…</i> <tt>…</tt>     emphasis, and <tt> for commands/paths
//   <ul><li>…</li></ul>              lists, for failure modes and steps
//   <a href="https://…">…</a>        links, opened in a real browser
//
// Length is not a virtue, but neither is brevity: say what is actually needed.
// When one panel has more than about three screens of prose, split it with
// `sections` rather than making people scroll past what they did not want.
//
//   InfoButton {
//       title: "Run"
//       what: "…"; why: "…"; ifWrong: "…"
//       sections: [
//           { title: "Privileges", body: "…" },
//           { title: "Troubleshooting", body: "…" }
//       ]
//   }
//
// With no `sections` the panel is a single scrolling column, as before. With
// them it grows a tab bar: the three standard questions become "Overview" and
// each section gets its own tab.
Item {
    id: root

    property string title: ""
    property string what: ""
    property string why: ""
    property string ifWrong: ""

    // Extra tabs: [{ title: string, body: richtext }]. See the note above.
    property var sections: []

    // Nothing to say means no button, rather than an empty panel.
    readonly property bool hasContent:
        what !== "" || why !== "" || ifWrong !== "" || sections.length > 0

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

    // One body of rich text, scrollable, with working links.
    component Prose: ScrollView {
        id: prose
        property string body: ""
        clip: true
        contentWidth: availableWidth

        Label {
            width: prose.availableWidth
            text: prose.body
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            lineHeight: 1.3
            // RichText rather than StyledText: StyledText has no lists, and
            // failure modes read far better as a list than as a paragraph.
            textFormat: Text.RichText
            linkColor: palette.link
            // Opened in the user's browser rather than rendered in-app. The
            // wasm build has no business navigating its own canvas away, and
            // a dashboard is not a web browser.
            onLinkActivated: function(url) { Qt.openUrlExternally(url) }

            // Hover feedback for links without swallowing their clicks:
            // NoButton means this area tracks the pointer and nothing else.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: parent.hoveredLink !== ""
                             ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
        }
    }

    Popup {
        id: panel
        // Parented to the overlay so the panel is never clipped by the
        // card it belongs to.
        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        // Wider and taller than the original 460px box: these carry real
        // prose now, and a narrow column of it is harder to read, not easier.
        width: Math.min(720, parent.width - 60)
        height: Math.min(contentColumn.wanted, parent.height - 80)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 16

        onOpened: bar.currentIndex = 0

        contentItem: ColumnLayout {
            id: contentColumn
            spacing: 10

            // Enough for the content when it is short, capped by the Popup
            // when it is not - so a one-line panel is not a half-screen box.
            readonly property int wanted:
                root.sections.length > 0 ? 560
              : (root.what.length + root.why.length + root.ifWrong.length) > 700
                ? 520 : 360

            Label {
                Layout.fillWidth: true
                text: root.title
                font.bold: true
                font.pixelSize: 15
                wrapMode: Text.WordWrap
            }

            // Tabs only when there is something to tab between. One tab is
            // just a label taking up room.
            TabBar {
                id: bar
                Layout.fillWidth: true
                visible: root.sections.length > 0
                TabButton { text: "Overview"; width: implicitWidth }
                Repeater {
                    model: root.sections
                    TabButton { text: modelData.title; width: implicitWidth }
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: bar.visible ? bar.currentIndex : 0

                // Overview: the three standard questions, stacked.
                ScrollView {
                    id: overview
                    clip: true
                    contentWidth: availableWidth

                    Column {
                        width: overview.availableWidth
                        spacing: 12

                        Repeater {
                            model: [
                                { heading: "What it is",        body: root.what },
                                { heading: "Why it matters",    body: root.why },
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
                                    lineHeight: 1.3
                                    textFormat: Text.RichText
                                    linkColor: palette.link
                                    onLinkActivated: function(url) {
                                        Qt.openUrlExternally(url)
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.NoButton
                                        cursorShape: parent.hoveredLink !== ""
                                                     ? Qt.PointingHandCursor
                                                     : Qt.ArrowCursor
                                    }
                                }
                            }
                        }
                    }
                }

                Repeater {
                    model: root.sections
                    Prose { body: modelData.body }
                }
            }

            Button {
                Layout.alignment: Qt.AlignRight
                text: "Close"
                onClicked: panel.close()
            }
        }
    }
}
