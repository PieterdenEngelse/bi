import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// System-wide additions — the third and most careful writable section.
//
// `/etc/nixos` is where a bad write costs a boot, so nothing here writes
// there directly. A switch prepares a file in your home; putting it into
// /etc is a separate action that asks for a password, and a rebuild applies
// it after that.
//
// **Three states, never collapsed.** Prepared, installed, in effect. Each is
// a different fact, and showing only the switch would claim a change that has
// not happened yet.
Rectangle {
    id: root

    Style { id: style }

    property string apiBase: ""
    signal changed()

    property var entries: []
    property string stagedPath: ""
    property string installedPath: ""
    /// Whether configuration.nix actually imports the generated file. Without
    /// that line everything here is inert.
    property bool imported: false
    property string lastError: ""
    property var busy: ({})

    implicitHeight: col.implicitHeight + 24
    radius: 8
    color: palette.base
    border.color: palette.mid

    Component.onCompleted: reload()

    function reload() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", root.apiBase + "/api/system")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status !== 200) {
                root.lastError = "could not read system options (HTTP "
                                 + xhr.status + ")"
                return
            }
            try {
                var d = JSON.parse(xhr.responseText)
                root.entries = d.entries
                root.stagedPath = d.staged_path
                root.installedPath = d.installed_path
                root.imported = d.imported === true
                root.lastError = ""
            } catch (e) {
                root.lastError = "bad response: " + e
            }
        }
        xhr.send()
    }

    function setBusy(key, value) {
        var next = {}
        for (var k in root.busy) next[k] = root.busy[k]
        next[key] = value
        root.busy = next
    }

    function toggle(key, enabled) {
        root.setBusy(key, true)
        var xhr = new XMLHttpRequest()
        xhr.open("POST", root.apiBase + "/api/system")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            root.setBusy(key, false)
            try {
                var d = JSON.parse(xhr.responseText)
                if (xhr.status === 200) {
                    root.lastError = ""
                    root.reload()
                    root.changed()
                } else {
                    root.lastError = d.error || ("HTTP " + xhr.status)
                    root.reload()
                }
            } catch (e) {
                root.lastError = xhr.status === 0 ? "cannot reach the app"
                                                  : "HTTP " + xhr.status
            }
        }
        xhr.send(JSON.stringify({ key: key, enabled: enabled }))
    }

    // Where a row has got to. Ordered, so the label always names the next
    // thing that has to happen rather than the last thing that did.
    function stageOf(e) {
        if (e.live === true) return "live"
        if (e.installed === true) return "installed"
        if (e.staged === true) return "prepared"
        return "off"
    }
    readonly property bool anyPrepared: {
        for (var i = 0; i < entries.length; ++i)
            if (stageOf(entries[i]) === "prepared") return true
        return false
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Label {
                text: "System-wide"
                font.bold: true
                font.pixelSize: 14
            }
            InfoButton {
                title: "Changing system configuration"
                what: "Additions that apply to the whole machine rather than \
to one project. Switching one on prepares a file in your home; it is not \
installed and not in effect until two further steps happen, each of which \
this section shows."
                why: "System configuration is the one place a bad write can \
stop the machine booting. So the app never writes there. It prepares a file, \
and installing it is a separate action that asks for your password - the \
prompt is what permits it, and refusing leaves everything untouched."
                ifWrong: "<ul>\
<li><b>Switched on but nothing happened.</b> Correct - preparing is not \
installing. An install action appears under Suggested actions.</li>\
<li><b>Installed but still not in effect.</b> The machine is built from its \
configuration, not watched. A rebuild applies it.</li>\
<li><b>Everything says done, but the value has not changed.</b> Check the \
warning above - if the system configuration does not import the prepared \
file, it is inert.</li></ul>"
                sections: [
                    { title: "The three steps", body: "\
<table cellpadding='5'>\
<tr><td><b>Prepared</b></td><td>Written to a file in your home. Instant, \
needs no password, changes nothing.</td></tr>\
<tr><td><b>Installed</b></td><td>Copied into the system configuration \
directory. Needs root, so polkit asks - this is the only step that touches \
anything outside your home.</td></tr>\
<tr><td><b>In effect</b></td><td>The machine has been rebuilt and the app \
can see the result. Confirmed by a value elsewhere in the app rather than \
assumed.</td></tr>\
</table><br>\
They are separate because each can fail or be refused independently, and \
because collapsing them would mean telling you something was done when it \
was merely written down." },
                    { title: "Why this is safe to use", body: "\
The usual objection to an app editing system configuration is that a mistake \
leaves you at a boot prompt. Four things make that not apply here, and each \
is checked by a test rather than promised in a comment.<br><br>\
<b>It never edits your configuration file.</b> It owns one generated file \
that yours imports. The hand-written one is not read, parsed or \
rewritten.<br><br>\
<b>It can only add packages and environment variables.</b> The generated \
file is produced from a fixed list and can contain nothing else - no boot \
settings, no filesystems, no users, no services, no kernel options. A file \
that can only put a program on your PATH cannot stop the machine \
starting.<br><br>\
<b>It writes only in your home.</b> Everything under the system directory \
arrives through one explicit copy, behind a password prompt you can \
refuse.<br><br>\
<b>Undoing it is the same action.</b> The file is rewritten whole, so \
switching everything off and installing again produces an empty file that \
removes what it added." },
                    { title: "System or project?", body: "\
Some additions can be made either way, and the right choice depends on \
where the thing using them lives.<br><br>\
<b>System-wide</b> suits a tool installed for the whole machine - an editor \
language server, for instance, which is not tied to one project and should \
work in any directory you open.<br><br>\
<b>Per project</b> suits anything a particular build needs, especially when \
different projects want different versions. That is the Development shell \
section above, and it needs no password at all because it only touches files \
you own.<br><br>\
Doing both is harmless but pointless: the project setting wins inside that \
project, and the system one covers everywhere else." }
                ]
            }
            Item { Layout.fillWidth: true }
            Label {
                visible: root.anyPrepared
                text: "prepared — not installed"
                font.pixelSize: 10
                color: style.pendingText
                padding: 3
                background: Rectangle { color: style.pendingTint; radius: 3 }
            }
        }

        // The quiet failure this section can have: a prepared and installed
        // file that nothing imports does nothing at all, and a rebuild gives
        // no hint why.
        Rectangle {
            Layout.fillWidth: true
            visible: !root.imported
            implicitHeight: notImported.implicitHeight + 12
            radius: 4
            color: style.badTint
            border.color: style.badDot
            Label {
                id: notImported
                x: 8; y: 6
                width: parent.width - 16
                wrapMode: Text.WordWrap
                font.pixelSize: 11
                color: style.badText
                text: "The system configuration does not import "
                      + root.installedPath + " yet, so anything prepared here "
                      + "will have no effect. Add it to the imports list "
                      + "first — that edit needs root and is not something "
                      + "this app does."
            }
        }

        Label {
            Layout.fillWidth: true
            text: root.stagedPath === "" ? "" : "prepared in " + root.stagedPath
            font.pixelSize: 10
            opacity: 0.55
            elide: Text.ElideMiddle
        }

        Label {
            Layout.fillWidth: true
            visible: root.lastError !== ""
            text: "✗ " + root.lastError
            color: style.badText
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.entries

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    text: modelData.label
                    font.pixelSize: 12
                    Layout.preferredWidth: 250
                }

                // [label] [control] [info], the same rhythm as every other
                // writable row.
                Switch {
                    checked: modelData.staged === true
                    // Never disabled while saving - see DevShellSection. This
                    // one only writes a file in your home, so an extra toggle
                    // costs nothing; the privileged step is a separate action.
                    // onToggled, not onCheckedChanged: the latter fires when
                    // the binding refreshes after a reload and would write
                    // back what was just read.
                    onToggled: root.toggle(modelData.key, checked)
                }

                InfoButton {
                    Layout.alignment: Qt.AlignVCenter
                    title: modelData.label
                    what: modelData.what
                    why: modelData.why
                    ifWrong: modelData.if_wrong
                }

                Label {
                    Layout.fillWidth: true
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    text: {
                        if (root.busy[modelData.key] === true)
                            return "saving…"
                        var s = root.stageOf(modelData)
                        if (s === "live")      return "✓ in effect"
                        if (s === "installed") return "installed — rebuild to apply"
                        if (s === "prepared")  return "prepared — needs installing"
                        return ""
                    }
                    color: root.stageOf(modelData) === "live" ? style.okText : style.pendingText
                }
            }
        }
    }
}
