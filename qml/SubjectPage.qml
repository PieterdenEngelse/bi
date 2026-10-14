import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One subject's panels, plus its actions.
//
// Panel components are chosen by id where a bespoke visual earns its place,
// and fall back to GenericPanel otherwise - so a panel added to the engine
// shows up here without a UI change, just without a chart.
Item {
    id: root

    property string subject: ""
    property var panels: []
    property var actions: []
    property var actionErrors: []
    property var memoryHistory: []
    property string apiBase: ""

    // A run changes exactly the state the panels show, so the shell re-polls.
    signal ranAction()

    readonly property var titles: ({
        "nixos": "NixOS",
        "qt": "Qt",
        "rust": "Rust"
    })

    ScrollView {
        id: scroller
        anchors.fill: parent
        anchors.margins: 14
        contentWidth: availableWidth

        // Wrapped rather than being the ScrollView's content item directly.
        // ScrollView sizes its content item, which fights a Layout that also
        // assigns its own `width`: the cap stopped applying and panels ran
        // off the right edge. A plain Item absorbs the sizing instead.
        Item {
            width: scroller.availableWidth
            implicitHeight: colLayout.implicitHeight

            ColumnLayout {
                id: colLayout
                // Full width. Was capped at 1700; extra width here becomes
                // another column of panels rather than longer lines, so the
                // grid absorbs it rather than stretching.
                width: parent.width
                spacing: 12

                SelectableText {
                    text: root.titles[root.subject] || root.subject
                    font.bold: true
                    font.pixelSize: 18
                }

                GridLayout {
                    Layout.fillWidth: true
                    // A third column once there is room for one at a readable
                    // width. Panels hold label/value rows, so widening them past
                    // ~550px just pushes the value away from its label.
                    columns: root.width < 640 ? 1 : (root.width >= 1500 ? 3 : 2)
                    columnSpacing: 12
                    rowSpacing: 12

                    Repeater {
                        model: root.panels

                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 200

                            property var summary: modelData

                            sourceComponent: {
                                switch (modelData.id) {
                                case "memory":       return memoryComp
                                case "failed-units": return unitsComp
                                case "generations":  return gensComp
                                case "disk":         return diskComp
                                case "qt":           return qtComp
                                case "rust":         return rustComp
                                default:             return genericComp
                                }
                            }
                        }
                    }
                }

                // Actions belonging to this subject. Same component the Config
                // page uses, so running works identically in both places.
                ActionsPanel {
                    id: actionsPanel
                    Layout.fillWidth: true
                    // Sizes to its content: the page already scrolls, so a fixed
                    // 300 only buys a second scrollbar and a clipped last action.
                    Layout.preferredHeight: actionsPanel.implicitHeight
                    visible: root.actions.length > 0 || root.actionErrors.length > 0
                    actions: root.actions
                    errors: root.actionErrors
                    apiBase: root.apiBase
                    onRanAction: root.ranAction()
                }
            }
        }
    }

    // Every panel now takes the whole summary: the engine supplies title,
    // headline, severity and the explanations, so the UI stops duplicating
    // judgement it has no business making.
    Component {
        id: memoryComp
        MemoryPanel { summary: parent.summary; history: root.memoryHistory }
    }
    Component {
        id: unitsComp
        FailedUnitsPanel { summary: parent.summary }
    }
    Component {
        id: gensComp
        GenerationsPanel { summary: parent.summary }
    }
    Component {
        id: diskComp
        DiskPanel { summary: parent.summary }
    }
    Component {
        id: qtComp
        QtPanel { summary: parent.summary }
    }
    Component {
        id: rustComp
        RustPanel { summary: parent.summary }
    }
    Component {
        id: genericComp
        GenericPanel { summary: parent.summary }
    }
}
