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

    Style { id: style }

    /// Prose bodies are rendered by a TextEdit so they can be selected and
    /// copied - info panels are full of commands and paths, and reading one
    /// off the screen by hand is not a feature. TextEdit has neither
    /// `linkColor` nor `lineHeight` (checked against Qt 6.11's own type
    /// info), so both move into the markup here: anchors get an inline
    /// colour, and the body is wrapped in a div carrying the line spacing.
    /// Qt ignores CSS it does not implement rather than erroring, so the
    /// worst case is tighter lines, not a broken panel.
    function proseHtml(body) {
        return "<div style='line-height:130%'>"
             + String(body).replace(/<a /g, "<a style='color:" + style.link + "' ")
             + "</div>"
    }

    implicitWidth: style.infoSize
    implicitHeight: style.infoSize
    visible: hasContent

    // The canonical spec, kept identical to the RERAG repo's so the two
    // dashboards read as the same family: a rounded square in the Rust brand
    // colour with a white glyph. It used to be a faint bordered circle that
    // took its colour from the palette, which made the single most important
    // affordance in the app the least visible thing on the row.
    Rectangle {
        id: dot
        anchors.fill: parent
        radius: 4
        color: style.infoBg
        border.color: style.infoBorder
        border.width: 1
        opacity: hover.hovered ? 0.8 : 1.0

        // Drawn rather than loaded: an SVG asset would be a second file to
        // keep in sync across two build systems for twelve lines of geometry.
        // Proportions follow the spec - circle r=9, stem from y=8 to y=14,
        // dot at cy=6.3 r=1, on a 24-unit grid.
        Canvas {
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                var s = width / 24
                ctx.reset()
                ctx.strokeStyle = style.infoGlyph
                ctx.fillStyle = style.infoGlyph
                ctx.lineWidth = 1.5 * s
                ctx.lineCap = "round"

                ctx.beginPath()
                ctx.arc(12 * s, 12 * s, 9 * s, 0, 2 * Math.PI)
                ctx.stroke()

                ctx.beginPath()
                ctx.moveTo(12 * s, 10 * s)
                ctx.lineTo(12 * s, 16.5 * s)
                ctx.stroke()

                ctx.beginPath()
                ctx.arc(12 * s, 7.8 * s, 1.1 * s, 0, 2 * Math.PI)
                ctx.fill()
            }
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

        SelectableText {
            width: prose.availableWidth
            text: prose.body
            font.pixelSize: 12
            wrapMode: TextEdit.Wrap
            // RichText rather than StyledText: StyledText has no lists, and
            // failure modes read far better as a list than as a paragraph.
            textFormat: TextEdit.RichText
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

            SelectableText {
                Layout.fillWidth: true
                text: root.title
                font.bold: true
                font.pixelSize: 15
                wrapMode: TextEdit.Wrap
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

                                SelectableText {
                                    text: modelData.heading
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                                SelectableText {
                                    width: parent.width
                                    text: root.proseHtml(modelData.body)
                                    font.pixelSize: 12
                                    wrapMode: TextEdit.Wrap
                                    textFormat: TextEdit.RichText
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
                    Prose { body: root.proseHtml(modelData.body) }
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
