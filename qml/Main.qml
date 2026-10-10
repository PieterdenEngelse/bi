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

    // Every colour in the app comes from here. Not a singleton: cxx-qt 0.10
    // cannot register one, so each component instantiates its own - see
    // Style.qml.
    Style { id: style }

    // A dark scheme chosen outright, rather than inherited from the desktop.
    //
    // It used to read the system palette and then paint tiles with
    // light-assuming literals (#fcf8e3, #fdecea), which looked fine only
    // because the session theme happened to be light - under a dark one the
    // app became dark chrome with pale islands in it.
    //
    // Fusion is set in main.rs before the engine starts. It is the built-in
    // style that takes its colours from the palette, so setting it here
    // reaches every button, switch, tab and combo box without styling them
    // one at a time.
    palette.window: style.window
    palette.base: style.surface
    palette.alternateBase: style.surfaceAlt
    palette.text: style.text
    palette.windowText: style.text
    palette.buttonText: style.text
    palette.button: style.surfaceAlt
    palette.mid: style.border
    palette.midlight: style.borderSoft
    palette.dark: style.window
    palette.light: style.surfaceAlt
    palette.highlight: style.link
    palette.highlightedText: style.window
    palette.link: style.link
    palette.linkVisited: style.linkHover
    palette.placeholderText: style.textMuted
    palette.toolTipBase: style.surfaceAlt
    palette.toolTipText: style.text

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

            // The window's own behaviour, including the two keyboard
            // shortcuts. A shortcut with no visible control is undiscoverable
            // by definition, so this is the affordance F11 would otherwise
            // not have.
            InfoButton {
                title: "This window"
                what: "Opens maximised, filling the screen below your panel. \
<b>F11</b> switches to true fullscreen - no title bar, covering the panel - \
and F11 or <b>Escape</b> comes back. Closing the window does not stop \
monitoring."
                why: "The engine is a separate background service that keeps \
sampling whether or not a window is open, so closing this loses nothing but \
the view. Maximised rather than fullscreen by default because fullscreen \
hides the title bar, leaving no visible way to close or move the window - a \
poor default for something you open to glance at."
                ifWrong: "<ul>\
<li><b>F11 does something unexpected.</b> On this machine the key marked \
PrtScrn reports itself as F11, so pressing it here toggles fullscreen rather \
than taking a screenshot.</li>\
<li><b>The window seems stuck covering everything.</b> Press Escape.</li>\
<li><b>It opens small.</b> You are running an older build - see Refresh \
&rarr; Deploying.</li></ul>"
                sections: [
                    { title: "The two windows", body: "\
This is the <b>desktop</b> build: Rust and Qt/QML compiled natively, talking \
to the engine over loopback HTTP.<br><br>\
There is a second one. The same QML is compiled to \
<a href='https://webassembly.org/'>WebAssembly</a> and runs in a browser, \
served from another loopback port. Both read the same engine, so they always \
agree - and they are built from one <tt>qml/</tt> directory, symlinked into \
each crate rather than copied, so an edit reaches both.<br><br>\
They differ only in how they are built: the desktop one is pure Cargo, the \
browser one needs CMake, corrosion, and a Qt cross-compiled for Emscripten. \
That second toolchain is the reason the Qt and Rust panels exist at all - \
every trap in getting it working is a value one of them now reports.<br><br>\
See <a href='https://doc.qt.io/qt-6/'>the Qt 6 documentation</a>." },
                    { title: "Privacy", body: "\
<ul>\
<li><b>Loopback only.</b> The engine binds <tt>127.0.0.1</tt> \
unconditionally - it is not a setting. It has no authentication and no TLS, \
so it must never be reachable from anywhere else.</li>\
<li><b>No accounts, no telemetry, no network calls.</b> Every panel reads \
local state: <tt>/proc</tt>, <tt>systemctl</tt>, \
<tt>/nix/var/nix/profiles</tt>, <tt>statvfs</tt>, <tt>qmake</tt>, \
<tt>rustc</tt>. Nothing is sent anywhere and the engine fetches \
nothing.</li>\
<li><b>No stored data.</b> History lives in memory and is lost on \
restart.</li>\
<li><b>No privilege of its own.</b> It runs as you and reads only what you \
could already read. It can start a privileged action, but only through a \
polkit prompt you answer.</li>\
</ul>\
Links in these panels are the one exception: following one opens your \
browser and contacts that site, like any other link." }
                ]
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
            // Why there are two pages at all, and why one of them refuses to
            // let you type into it - which is the thing people expect and do
            // not get.
            InfoButton {
                title: "Monitor and Config"
                what: "Two questions asked at different times.<br><br>\
<b>Monitor</b> answers <i>is anything wrong right now</i> - one card per \
subject, each showing its unhappiest panel.<br>\
<b>Config</b> answers <i>how is this set up, and what would I change</i> - \
what is in effect, and which file declares it."
                why: "A single grid gives every panel equal weight, so \
<i>Qt prefix complete</i> and <i>disk at 95%</i> look identical until you \
read both. Monitor exists so that most of the time you can read nothing and \
move on."
                ifWrong: "<b>Config is deliberately not a settings form.</b> \
This machine is configured declaratively, so a field you could type into \
would either write somewhere Nix later overwrites, or fight Nix outright - \
either way lying about where configuration lives. It shows values, says which \
file they come from, and hands you a snippet."
                sections: [
                    { title: "The three subjects", body: "\
Monitoring is split by subject because the questions are genuinely \
different.<br><br>\
<b>NixOS</b> - is this machine healthy? Memory and stall pressure, failed \
units in both scopes, generations and whether a reboot is pending, free space \
on the store's filesystem. Most of the actions live here, and they are the \
ones that can be run.<br><br>\
<b>Qt</b> and <b>Rust</b> - <i>will a build work in this environment?</i> \
Not <i>is it installed</i>. That distinction is the whole point: a Qt prefix \
can be present, correct and still missing the host tools <tt>cxx-qt</tt> \
needs, because on NixOS <tt>qmltyperegistrar</tt> and <tt>qmlcachegen</tt> \
live in qtdeclarative rather than qtbase - and the build fails late, naming \
the tool rather than the prefix.<br><br>\
Both describe the <b>engine's</b> environment, which is the background \
service's - not whichever shell you are sitting in. A devShell with a \
complete prefix will not change what those panels say. That is a real \
limitation, stated plainly rather than papered over.<br><br>\
References: <a href='https://nixos.org/manual/nixos/stable/'>NixOS \
manual</a> &middot; <a href='https://doc.qt.io/qt-6/'>Qt 6</a> &middot; \
<a href='https://doc.rust-lang.org/rustc/platform-support.html'>Rust \
platform support</a>" }
                ]
            }

            Item { Layout.fillWidth: true }

            Label {
                text: root.engineUp ? dash.apiBase : root.lastError
                color: root.engineUp ? palette.text : style.badDot
                font.pixelSize: 11
                opacity: root.engineUp ? 0.55 : 1.0
                elide: Text.ElideLeft
                Layout.maximumWidth: 260
            }

            Button { text: "Refresh"; onClicked: root.refresh() }
            // The name promises more than it does, so it needs saying: this
            // re-reads the engine, it does not re-measure the machine.
            InfoButton {
                title: "Refresh"
                what: "Re-fetches the engine's latest samples immediately. \
This window already polls every 2 seconds, so mostly it saves you a short \
wait."
                why: "It does <b>not</b> make the engine re-measure \
anything. Each panel is sampled on its own schedule by the background \
service, and this button shows whatever that schedule last produced. A disk \
figure can legitimately be half a minute old the instant after you press it."
                ifWrong: "<ul>\
<li><b>A value will not move.</b> Check its panel's interval below before \
suspecting the engine - 60s panels look frozen next to a 2s one.</li>\
<li><b>The address to the left is red.</b> The window is not reaching the \
engine at all; nothing will update until it comes back. Check \
<tt>systemctl --user status nixdash-engine</tt>.</li>\
<li><b>Everything is stale after a rebuild.</b> A changed service keeps \
running the old build until restarted - see the Deploying tab.</li></ul>"
                sections: [
                    { title: "Sampling", body: "\
Collection happens in the engine, not here. Each panel declares its own \
interval, chosen against what the measurement costs:<br><br>\
<table cellpadding='4'>\
<tr><td><b>Panel</b></td><td><b>Every</b></td><td><b>Why that \
interval</b></td></tr>\
<tr><td>memory</td><td>2s</td><td>two cheap reads of <tt>/proc</tt>; the only \
one that moves fast enough to watch</td></tr>\
<tr><td>failed-units</td><td>15s</td><td>shells out to <tt>systemctl</tt> \
twice, user and system scope</td></tr>\
<tr><td>disk</td><td>30s</td><td>one <tt>statvfs</tt>, but it changes \
slowly</td></tr>\
<tr><td>generations</td><td>60s</td><td>a directory listing; changes only \
when you rebuild</td></tr>\
<tr><td>qt</td><td>60s</td><td>runs <tt>qmake -query</tt></td></tr>\
<tr><td>rust</td><td>60s</td><td>runs <tt>rustc</tt> and \
<tt>cargo</tt></td></tr>\
</table><br>\
History is kept in memory only, and is lost when the engine restarts. \
Nothing is written to disk and nothing leaves the machine.<br><br>\
Severity and the one-line headline are also decided in the engine, not in \
this window - so the desktop and browser builds cannot disagree about what a \
number means." },
                    { title: "Deploying", body: "\
Changes to the project do not appear here until they are built and picked \
up.<br><br>\
<b>Any file in the repository</b> - <tt>home-manager switch</tt>, then the \
restart it prints:<br><tt>systemctl --user restart \
nixdash-engine.service</tt><br>\
The engine's Nix source is the whole tree, so editing <i>any</i> file \
rebuilds it to a new store path. Your <tt>home.nix</tt> sets \
<tt>startServices = \"suggest\"</tt>, which means home-manager prints that \
command rather than running it - restarting services automatically takes \
xfconf down and kills the Xfce panel on this machine.<br><br>\
<b>Changes to this window</b> - also close and reopen it. The UI is an \
ordinary desktop app, not a service, so a restart command does nothing for \
it.<br><br>\
<b>Panel icon or menu entry</b> - also <tt>xfce4-panel -r</tt>. New plugins \
are not drawn live.<br><br>\
Until you do those, a changed service keeps running the <i>old</i> build and \
everything here will look untouched." }
                ]
            }
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
