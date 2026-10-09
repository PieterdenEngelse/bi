import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import nixdash

// Shell: owns the data and the navigation state. The pages below are
// presentational - they receive data as properties and emit navigation
// requests, which keeps fetching in one place instead of three.
ApplicationWindow {
    id: root
    // The size the window returns to when un-maximised, not the size it
    // opens at - see `visibility` below.
    width: 820
    height: 700
    visible: true
    title: "nixdash"

    // Opens filling the screen.
    //
    // Maximized, NOT FullScreen. True fullscreen drops the title bar and
    // covers the panel, which leaves no visible way to close, move or get
    // past the window - a poor default for something you open to glance at
    // and then leave. F11 below gives you the real thing when you want it,
    // which is the usual place to look for it.
    visibility: Window.Maximized

    Shortcut {
        sequences: [ "F11" ]
        onActivated: root.visibility =
            root.visibility === Window.FullScreen ? Window.Maximized
                                                  : Window.FullScreen
    }
    // Escape only ever leaves fullscreen - it must not close the window, or
    // a stray keypress loses the window you just opened.
    Shortcut {
        sequences: [ "Escape" ]
        enabled: root.visibility === Window.FullScreen
        onActivated: root.visibility = Window.Maximized
    }

    // Rust supplies the engine's address; see ui/src/cxxqt_object.rs.
    Dash { id: dash }

    // ---- data ----------------------------------------------------------
    property bool engineUp: false
    property string lastError: ""
    property var panels: []          // raw summaries from the engine
    property var actions: []
    property var actionErrors: []
    property var memoryHistory: []

    // ---- navigation ----------------------------------------------------
    // Two levels is the whole hierarchy: a top tab, and optionally one
    // subject drilled into. A router would be structure for its own sake.
    property string tab: "monitor"   // "monitor" | "config"
    property string subject: ""      // "" = overview; else nixos|qt|rust

    function panelsFor(subj) {
        return panels.filter(function(p) { return p.subject === subj })
    }
    function actionsFor(subj) {
        return actions.filter(function(a) { return a.subject === subj })
    }
    function actionCount(subj) {
        return actionsFor(subj).length
    }

    function getJson(path, onOk) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", dash.apiBase + path)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status === 200) {
                root.engineUp = true
                root.lastError = ""
                try { onOk(JSON.parse(xhr.responseText)) }
                catch (e) { root.lastError = "bad response: " + e }
            } else {
                root.engineUp = false
                root.lastError = xhr.status === 0
                    ? "engine unreachable at " + dash.apiBase
                    : "HTTP " + xhr.status
            }
        }
        xhr.send()
    }

    function refresh() {
        getJson("/api/panels", function(d) { root.panels = d.panels })
        getJson("/api/actions", function(d) {
            root.actions = d.actions
            root.actionErrors = d.errors
        })
        // Only needed by the memory panel's sparkline; ~3 minutes at 2s.
        getJson("/api/panels/memory?limit=90", function(d) {
            root.memoryHistory = d.samples
        })
    }

    Component.onCompleted: refresh()
    Timer { interval: 2000; running: true; repeat: true; onTriggered: root.refresh() }

    header: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 6

            Button {
                text: "‹"
                visible: root.subject !== ""
                flat: true
                onClicked: root.subject = ""
            }

            Label {
                text: "nixdash"
                font.bold: true
                font.pixelSize: 15
            }

            TabBar {
                id: tabs
                Layout.leftMargin: 10
                currentIndex: root.tab === "monitor" ? 0 : 1
                // onClicked per button, not onCurrentIndexChanged: clicking
                // the tab you are already on must still return to its root,
                // and an index that does not change fires no signal.
                TabButton {
                    text: "Monitor"; width: 90
                    onClicked: { root.tab = "monitor"; root.subject = "" }
                }
                TabButton {
                    text: "Config"; width: 90
                    onClicked: { root.tab = "config"; root.subject = "" }
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                text: root.engineUp ? dash.apiBase : root.lastError
                color: root.engineUp ? palette.text : "#f44336"
                font.pixelSize: 11
                opacity: root.engineUp ? 0.55 : 1.0
                elide: Text.ElideLeft
                Layout.maximumWidth: 260
            }

            Button { text: "Refresh"; onClicked: root.refresh() }
        }
    }

    // One of three views: overview, a subject's panels, or config.
    Loader {
        anchors.fill: parent
        sourceComponent: root.tab === "config" ? configPage
                       : root.subject === ""   ? monitorPage
                       : subjectPage
    }

    Component {
        id: monitorPage
        MonitorPage {
            panels: root.panels
            actions: root.actions
            onOpenSubject: function(s) { root.subject = s }
        }
    }

    Component {
        id: subjectPage
        SubjectPage {
            subject: root.subject
            panels: root.panelsFor(root.subject)
            actions: root.actionsFor(root.subject)
            actionErrors: root.actionErrors
            memoryHistory: root.memoryHistory
            apiBase: dash.apiBase
            // Without this the panel that triggered the change would keep
            // showing the state that justified the action - a restarted unit
            // still listed as failed.
            onRanAction: root.refresh()
        }
    }

    Component {
        id: configPage
        ConfigPage {
            panels: root.panels
            actions: root.actions
            apiBase: dash.apiBase
            onRanAction: root.refresh()
        }
    }
}
