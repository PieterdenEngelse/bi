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

    /// Size for the header's chrome text: the two tabs, and the About link
    /// beside them. Six pixels up from the inherited font rather than a
    /// literal, so it keeps its distance if that font changes - the default
    /// here is whatever Gtk/FontName says, "Sans 8" on this machine, which
    /// is about 11px at 96dpi, putting this at roughly 17.
    ///
    /// It was +2 first and that was too small to notice, which is the whole
    /// argument for the offset living in one named place.
    ///
    /// The guard is not decoration. `font.pixelSize` reads -1 when the font
    /// it resolved was specified in POINTS, which is exactly how a
    /// Gtk/FontName arrives - without it this would be a 1px header.
    readonly property int chromeFont:
        (root.font.pixelSize > 0 ? root.font.pixelSize : 11) + 6

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

    // Ctrl+C and Ctrl+A act on the focused value, explicitly rather than by
    // leaving either to that item's own key handling. Every value here is a
    // READ-ONLY TextEdit, and a read-only TextEdit leaves selectByKeyboard
    // false - the state in which both keys do nothing at all.
    //
    // selectByKeyboard: true would have enabled both natively, at the price
    // of a blinking text cursor sitting in whichever value was last clicked.
    // In a window whose values are all read-only readings, a cursor says
    // "type here", so these two shortcuts buy the same behaviour without it.
    //
    // One Shortcut each for the whole window, not one per panel: two enabled
    // shortcuts on the same sequence are ambiguous and then NEITHER fires,
    // which is the same trap that makes Ctrl+Shift+C scope itself to the
    // pointer instead.

    /// The focused item, when it is a text item with a selection to act on.
    ///
    /// Duck-typed on purpose. activeFocusItem is typed QQuickItem, so qmllint
    /// reports selectedText, copy and selectAll as missing from it - the same
    /// complaint it makes about SelectableText's walk for a Flickable, and
    /// the same answer: QML resolves all three at runtime, a text item
    /// answers and anything else does not. Do not "fix" the warnings by
    /// dropping the probes; the probes are the guard.
    ///
    /// An editable field satisfies it too, so the port spinner keeps behaving
    /// the way its own Ctrl+C and Ctrl+A would.
    function focusedText() {
        var it = root.activeFocusItem
        // qmllint disable missing-property
        // Probing, not accessing: activeFocusItem is a plain Item until it
        // turns out to be a text one, which is the whole question here.
        return it && it.selectedText !== undefined
               && typeof it.copy === "function"
               && typeof it.selectAll === "function" ? it : null
        // qmllint enable missing-property
    }

    Shortcut {
        sequences: [ "Ctrl+C" ]
        onActivated: {
            // The live selection, not a remembered string: this copies what
            // is selected now.
            var t = root.focusedText()
            if (t && t.selectedText.length > 0)
                t.copy()
        }
    }

    // Selects the whole of ONE value - the one last clicked - because that is
    // as far as a selection reaches here: each reading is its own text item.
    // Ctrl+Shift+C remains the gesture for a whole pane.
    //
    // Deliberately does not copy. Dragging copies because releasing a drag is
    // an unambiguous "I want this"; Ctrl+A is the ordinary prelude to Ctrl+C
    // and in every other application leaves the clipboard alone, so making it
    // write would be a surprise that costs you what you had copied.
    Shortcut {
        sequences: [ "Ctrl+A" ]
        onActivated: {
            var t = root.focusedText()
            if (t)
                t.selectAll()
        }
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

    // Display names for the breadcrumb. MonitorPage and SubjectPage each
    // carry their own copy for their own labels; this is the third and the
    // one the header reads.
    readonly property var subjectNames: ({
        "nixos": "NixOS",
        "qt": "Qt",
        "rust": "Rust"
    })

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

    Component.onCompleted: { console.log(undefinedThing.nope); refresh() }
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

            SelectableText {
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
monitoring.<br><br>\
Every value in this window is <b>selectable</b>, and selecting <b>copies</b>: \
letting go of a drag puts that text on the clipboard, so <tt>Ctrl+V</tt> \
pastes it anywhere. <tt>Ctrl+C</tt> copies the selection again if you would \
rather use the keystroke. A click selects nothing and deliberately leaves the \
clipboard alone, so reading a value by tapping it cannot cost you what you \
had copied. On this desktop a <i>dragged</i> value also lands on the X11 \
primary selection, so a <b>middle-click</b> pastes it without either.<br><br>\
<tt>Ctrl+A</tt> selects the whole of the value you last clicked, ready for \
<tt>Ctrl+C</tt>; unlike dragging, it does not copy on its own.<br><br>\
A selection cannot cross from one value into the next, so for a whole panel \
at once, point at it and press <b>Ctrl+Shift+C</b> - that copies the pane \
under the pointer as tab-separated text."
                why: "The engine is a separate background service that keeps \
sampling whether or not a window is open, so closing this loses nothing but \
the view. Maximised rather than fullscreen by default because fullscreen \
hides the title bar, leaving no visible way to close or move the window - a \
poor default for something you open to glance at."
                ifWrong: "<ul>\
<li><b>Something you copied here vanished.</b> On this desktop the clipboard \
is held by the program that filled it, and nothing is running to outlive it - \
no clipboard manager. Closing this window therefore empties whatever you \
copied from it, with no error anywhere. Paste it before you close the window; \
the primary selection goes the same way for the same reason.</li>\
<li><b>Ctrl+Shift+C did nothing.</b> The pointer was not over a panel. It \
copies the pane you are pointing at, so there is no ambiguity about which \
one you meant.</li>\
<li><b>Ctrl+A or Ctrl+C did nothing.</b> Both act on the value you last \
clicked, and in a window you have only just opened that is nothing at all. \
Click a value first - a single click selects nothing and copies nothing, it \
only decides what the keys apply to.</li>\
<li><b>A dragged selection stops at the end of a value.</b> Expected. Each \
reading is its own piece of text - which is what lets each one carry its own \
info button - and Qt shares a selection only inside one piece. Ctrl+Shift+C \
is the gesture for more than one.</li>\
<li><b>Middle-click pastes something older.</b> The primary selection holds \
whatever was selected <i>last</i>, anywhere on the desktop - selecting in \
another window replaces it. In the browser build there is no primary \
selection at all, so there use Ctrl+C or Ctrl+Shift+C.</li>\
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
                    font.pixelSize: root.chromeFont
                    onClicked: { root.tab = "monitor"; root.subject = "" }
                }
                TabButton {
                    text: "Config"; width: 90
                    font.pixelSize: root.chromeFont
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

            // Where you are, as a trail. The tab bar says which of the two
            // pages you are on, but a subject's panels are a level below it
            // and the only thing naming them was the page's own heading -
            // which scrolls away. The first crumb is also the way back up.
            Row {
                id: crumbs
                spacing: 5
                Layout.leftMargin: 4
                Layout.alignment: Qt.AlignVCenter

                SelectableText {
                    text: root.tab === "monitor" ? "Monitor" : "Config"
                    font.pixelSize: style.fontBody
                    // Not dimmed when it is a parent rather than the place
                    // you are - see Style.qml. What is left to say so is the
                    // ordinary breadcrumb cue: the last crumb is where you
                    // are, and only the ones before it answer a click.

                    // No cursor change and no click on the overview, where
                    // this crumb leads nowhere. A pointing hand over a label
                    // that does nothing is a promise the click does not keep.
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.subject !== ""
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.subject = ""
                    }
                }

                Label {
                    text: "\u203a"
                    visible: root.subject !== ""
                    font.pixelSize: style.fontBody
                }

                SelectableText {
                    text: root.subjectNames[root.subject] || root.subject
                    visible: root.subject !== ""
                    font.pixelSize: style.fontBody
                    font.bold: true
                }
            }

            Item { Layout.fillWidth: true }

            // Right-aligned and clipped rather than elided-from-the-left:
            // TextEdit has no elide, and this keeps the tail visible exactly
            // as ElideLeft did, minus the ellipsis. Ctrl+A reaches the part
            // scrolled out of view, so the whole address or error can still
            // be copied.
            SelectableText {
                text: root.engineUp ? dash.apiBase : root.lastError
                color: root.engineUp ? palette.text : style.badDot
                font.pixelSize: style.fontBody
                horizontalAlignment: TextEdit.AlignRight
                wrapMode: TextEdit.NoWrap
                clip: true
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
<ul>\
<li><b>memory</b>, every 2s - two cheap reads of <tt>/proc</tt>; the only one \
that moves fast enough to watch</li>\
<li><b>failed-units</b>, every 15s - shells out to <tt>systemctl</tt> twice, \
user and system scope</li>\
<li><b>disk</b>, every 30s - one <tt>statvfs</tt>, but it changes slowly</li>\
<li><b>generations</b>, every 60s - a directory listing; changes only when \
you rebuild</li>\
<li><b>qt</b>, every 60s - runs <tt>qmake -query</tt></li>\
<li><b>rust</b>, every 60s - runs <tt>rustc</tt> and <tt>cargo</tt></li>\
</ul><br>\
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

            // Which build this window is. Last in the row, so it sits in the
            // top-right corner past the Refresh info button.
            //
            // A link rather than a fourth InfoButton: those explain the
            // control they sit beside, and this explains the program. It is
            // also the string you paste into a bug report, so the gesture is
            // ClickOrSelectArea's - click opens About, drag selects the
            // version - instead of a MouseArea that would swallow the drag.
            Item {
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: 2
                implicitWidth: buildText.implicitWidth
                implicitHeight: buildText.implicitHeight

                SelectableText {
                    id: buildText
                    text: "v" + dash.version + " \u00b7 " + dash.built
                    color: buildArea.hovered ? style.linkHover : style.link
                    font.pixelSize: root.chromeFont
                }

                ClickOrSelectArea {
                    id: buildArea
                    anchors.fill: parent
                    textItem: buildText
                    onActivated: about.open()
                }
            }
        }
    }

    // About. The version link in the header opens this; nothing else does.
    Popup {
        id: about
        // On the overlay, like InfoButton's panel, so the header cannot clip
        // it.
        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.min(460, parent.width - 60)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 16

        contentItem: ColumnLayout {
            spacing: 10

            SelectableText {
                Layout.fillWidth: true
                text: "nixdash"
                font.bold: true
                font.pixelSize: 15
            }

            SelectableText {
                Layout.fillWidth: true
                text: "A local-first dashboard for one NixOS machine: a Rust \
engine reads the system, this window renders it."
                font.pixelSize: style.fontBody
                wrapMode: TextEdit.Wrap
            }

            // Version and date describe THIS window, baked in at compile
            // time - see ui/build_date.rs. The engine is a separate binary
            // and can be a different build entirely, which is the usual
            // reason a change does not show up; the address is here so the
            // two can be told apart.
            Grid {
                columns: 2
                columnSpacing: 12
                rowSpacing: 4

                SelectableText { text: "version";  font.pixelSize: style.fontBody }
                SelectableText { text: dash.version; font.pixelSize: style.fontBody }
                // Amsterdam, not UTC - the EU rule is hardcoded in
                // ui/build_date.rs, which is the only zone this shows.
                SelectableText { text: "built";    font.pixelSize: style.fontBody }
                SelectableText {
                    text: dash.built + "  (Amsterdam)"
                    font.pixelSize: style.fontBody
                }
                SelectableText { text: "engine";   font.pixelSize: style.fontBody }
                SelectableText {
                    text: root.engineUp ? dash.apiBase
                                        : dash.apiBase + "  (unreachable)"
                    color: root.engineUp ? palette.text : style.badDot
                    font.pixelSize: style.fontBody
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.fillWidth: true }

                Button {
                    text: "Close"
                    onClicked: about.close()
                }
                // The dates are the point of this dialog, and a wrong one is
                // the usual explanation for "my change is not in here".
                InfoButton {
                    title: "About this build"
                    what: "Which build you are looking at. <b>version</b> is \
the app's own version; <b>built</b> is the day this window's build was \
produced, in Amsterdam time; <b>engine</b> is the address this window reads \
from, marked <i>unreachable</i> when nothing answers there."
                    why: "There is no other way to tell. A store path's \
timestamp is pinned to the epoch by design, and when a process started says \
when you opened the window - not when its binary was made. So <b>built</b> is \
the only answer to \"is this the code I just wrote?\", which is the question \
that costs an afternoon when two identical-looking windows are hours \
apart.<br><br>\
The background service shown as <b>engine</b> is a separate binary and can be \
a different build entirely; its address is here so the two can be told apart \
rather than assumed to match."
                    ifWrong: "<ul>\
<li><b>Older than your last build.</b> You are running the installed copy. \
The menu entry and the panel launcher start whichever is newer - a local \
<tt>cargo build</tt> only wins once it is newer than the generation \
<tt>home-manager switch</tt> installed.</li>\
<li><b>Today's date, but your change is missing.</b> This window's QML is \
baked into the binary when it is built, so an edit only arrives with a \
rebuild - and a brand-new QML file has to be listed in both UIs' build files \
or it is simply not in the bundle.</li>\
<li><b>engine marked unreachable.</b> Nothing is listening on that address: \
the background service is stopped, or running on a different port than this \
window was told about.</li></ul>"
                }
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
