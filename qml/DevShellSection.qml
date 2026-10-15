import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Optional additions to this project's development shell.
//
// The second writable section on this page, and it works the same way as the
// one above: the app owns a generated Nix file and rewrites it whole. It
// never edits flake.nix, which is hand-written and full of comments that are
// the only record of why some of those lines exist.
//
// **Enabled is not the same as present.** Turning one on edits a file; the
// shell you already have open is unchanged until you re-enter it. So each row
// carries two states - what is written, and whether the app can actually see
// the thing yet - and never conflates them.
Rectangle {
    id: root

    Style { id: style }

    property string apiBase: ""
    signal changed()

    property var extras: []
    property string filePath: ""
    property string lastError: ""
    property var busy: ({})

    implicitHeight: col.implicitHeight + 24
    radius: 8
    color: palette.base
    border.color: palette.mid

    Component.onCompleted: reload()

    function reload() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", root.apiBase + "/api/devshell")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status !== 200) {
                root.lastError = "could not read dev shell options (HTTP "
                                 + xhr.status + ")"
                return
            }
            try {
                var d = JSON.parse(xhr.responseText)
                root.extras = d.extras
                root.filePath = d.path
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
        xhr.open("POST", root.apiBase + "/api/devshell")
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

    // Written, but not yet visible in any shell the app can see.
    function waiting(e) {
        return e.enabled === true && e.live !== true
    }
    readonly property bool anyWaiting: {
        for (var i = 0; i < extras.length; ++i)
            if (waiting(extras[i])) return true
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
            SelectableText {
                text: "Development shell"
                font.bold: true
                font.pixelSize: 14
            }
            InfoButton {
                title: "Development shell additions"
                what: "Optional packages this project's development shell can \
carry. Switching one on writes a generated Nix file - \
<tt>nix/devshell-extras.nix</tt> - which the project's \
<tt>flake.nix</tt> imports and appends."
                why: "The flake itself is hand-written and carries comments \
that are the only record of why some of its lines exist. Nothing here \
edits that file: a generated list is rewritten whole, so there is nothing \
in it to corrupt. Only additions that can be checked afterwards are \
offered - each one has a value elsewhere in this app that proves it \
arrived."
                ifWrong: "<ul>\
<li><b>Switched on, but still reported missing.</b> Expected. The shell you \
have open was built when you entered it. Run <tt>nix develop</tt> \
again.</li>\
<li><b>It stays missing after a new shell.</b> Check that \
<tt>nix/devshell-extras.nix</tt> is tracked by git - an untracked file is \
invisible to a flake, and the failure looks nothing like a missing \
file.</li>\
<li><b>A switch snaps back.</b> The write was refused; the reason appears \
in red below.</li></ul>"
                sections: [
                    { title: "Written vs present", body: "\
Two different facts, and each row shows both.<br><br>\
<b>Written</b> - the switch position. The generated file says this package \
belongs in the shell. Instant, and harmless on its own.<br>\
<b>Present</b> - the package is actually there, confirmed by a value \
elsewhere in this app rather than assumed.<br><br>\
They differ for exactly as long as it takes you to re-enter the shell. A \
development shell is built when you enter it; nothing reaches back into one \
that is already running. Showing only the switch would mean claiming a \
change that has not happened yet, which is the thing this page exists to \
avoid.<br><br>\
<ul>\
<li><b>lld</b> - confirmed by the Rust panel's <tt>lld available</tt></li>\
<li><b>rust-src</b> - confirmed by the Rust panel's standard library \
sources</li>\
</ul>" },
                    { title: "Why only these two", body: "\
Anything offered here has to be checkable afterwards. Both of these have a \
value elsewhere in the app that flips once the package arrives, so \"did \
that work?\" has an answer you can see rather than one you have to take on \
trust.<br><br>\
A package with nothing to confirm it would mean the app claiming to have \
changed something it cannot observe - which is how a monitoring tool starts \
lying to you.<br><br>\
Other suggestions - the Qt merged prefix, the Emscripten toolchain - stay \
copy-only. They belong in <i>other</i> projects' files, which this app \
cannot see and should not guess at. Those are shown as snippets under \
Suggested actions instead." }
                ]
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                visible: root.anyWaiting
                implicitWidth: waitingBadge.implicitWidth + 8
                implicitHeight: waitingBadge.implicitHeight + 6
                radius: 3
                color: style.pendingTint
                SelectableText {
                    id: waitingBadge
                    anchors.centerIn: parent
                    text: "re-enter the shell"
                    font.pixelSize: style.fontBody
                    color: style.pendingText
                }
            }
        }

        // The path is there to be opened, so it has to be copyable -
        // and wrapping rather than elided, since the middle of a store path
        // is not the part you can guess.
        SelectableText {
            Layout.fillWidth: true
            text: root.filePath === "" ? "" : "written to " + root.filePath
            font.pixelSize: style.fontBody
            wrapMode: TextEdit.Wrap
        }

        SelectableText {
            Layout.fillWidth: true
            visible: root.lastError !== ""
            text: "✗ " + root.lastError
            color: style.badText
            font.pixelSize: style.fontBody
            wrapMode: TextEdit.Wrap
        }

        Repeater {
            model: root.extras

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                SelectableText {
                    text: modelData.label
                    font.pixelSize: style.fontBody
                    Layout.preferredWidth: 250
                }

                // [label] [control] [info] - the control sits next to its
                // label, and the info button trails the thing it explains.
                Switch {
                    checked: modelData.enabled === true
                    // Never disabled while saving. A disabled control renders
                    // greyed and reads as *broken* rather than *busy*, and
                    // there is nothing to protect against anyway: the write
                    // sends an explicit desired state, so toggling twice in a
                    // row just writes twice and lands on what you chose.
                    // onToggled, not onCheckedChanged: the latter also fires
                    // when the binding updates after a reload, writing back
                    // what was just read, forever.
                    onToggled: root.toggle(modelData.key, checked)
                }

                InfoButton {
                    Layout.alignment: Qt.AlignVCenter
                    title: modelData.label
                    what: modelData.what
                    why: modelData.why
                    ifWrong: modelData.if_wrong
                }

                // The honest part: what the switch says, versus what is
                // actually in the shell. Also where "saving" is said, in
                // words, rather than by grey-ing the control out.
                SelectableText {
                    Layout.fillWidth: true
                    font.pixelSize: style.fontBody
                    text: {
                        if (root.busy[modelData.key] === true)
                            return "saving…"
                        if (modelData.live === true)
                            return "✓ present in the shell"
                        if (modelData.enabled === true)
                            return "written — not in this shell yet"
                        return ""
                    }
                    color: modelData.live === true ? style.okText : style.pendingText
                    wrapMode: TextEdit.NoWrap
                    clip: true
                }
            }
        }
    }
}
