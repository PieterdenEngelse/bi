import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// nixdash's own settings - the one part of the Config page you can change.
//
// Everything else on this page is read-only, and says why: the machine is
// configured declaratively, so a field writing to a live value would be a
// lie. These four are different only because the app owns the file they live
// in. It regenerates that file whole; it never edits hand-written Nix.
//
// **Changing a control here does not change the machine.** It rewrites Nix
// source. The value then sits "declared but not in effect" until a rebuild,
// and this section shows both so the gap is visible rather than surprising.
// That is not a limitation worked around - it is how a declarative system
// works, stated plainly.
Rectangle {
    id: root

    Style { id: style }

    property string apiBase: ""
    /// Emitted after a successful write, so the shell can re-poll actions -
    /// an unapplied change becomes an offered action.
    signal changed()

    property var settings: []
    property var effective: ({})
    property string filePath: ""
    property string lastError: ""
    /// key -> true while a write is in flight.
    property var busy: ({})

    implicitHeight: col.implicitHeight + 24
    radius: 8
    color: palette.base
    border.color: palette.mid

    Component.onCompleted: reload()

    function reload() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", root.apiBase + "/api/settings")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status !== 200) {
                root.lastError = "could not read settings (HTTP " + xhr.status + ")"
                return
            }
            try {
                var d = JSON.parse(xhr.responseText)
                root.settings = d.settings
                root.effective = d.effective
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

    function write(key, value) {
        root.setBusy(key, true)
        var xhr = new XMLHttpRequest()
        xhr.open("POST", root.apiBase + "/api/settings")
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
                    // The engine validates: a refusal carries the reason, and
                    // showing it is the whole point of refusing rather than
                    // silently clamping the value.
                    root.lastError = d.error || ("HTTP " + xhr.status)
                    root.reload()
                }
            } catch (e) {
                root.lastError = xhr.status === 0 ? "engine unreachable"
                                                  : "HTTP " + xhr.status
            }
        }
        xhr.send(JSON.stringify({ key: key, value: value }))
    }

    // Is this setting's declared value different from what is running?
    // Only port and logLevel have a running counterpart - the autostart flags
    // take effect at the next login, so there is nothing to compare.
    function pending(s) {
        if (s.declared === null || s.declared === undefined)
            return false
        if (s.key === "port")
            return root.effective.port !== undefined
                   && s.declared !== root.effective.port
        if (s.key === "logLevel") {
            var live = String(root.effective.logLevel || "")
            // The file holds a tuned RUST_LOG directive; the engine reports
            // it verbatim here, so compare against the part that is ours.
            var m = live.split(",").filter(function(p) {
                return p.trim().indexOf("nixdash_engine=") === 0
            })
            var level = m.length > 0 ? m[0].trim().substring(15) : live
            return s.declared !== level
        }
        return false
    }

    readonly property bool anyPending: {
        for (var i = 0; i < settings.length; ++i)
            if (pending(settings[i])) return true
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
                text: "nixdash itself"
                font.bold: true
                font.pixelSize: 14
            }
            InfoButton {
                title: "Changing nixdash's own settings"
                what: "These four write to a Nix file that nixdash generates \
and owns - <tt>~/.config/home-manager/nixdash-settings.nix</tt>. It is \
rewritten whole on every change, so a hand edit there will be lost."
                why: "Everything else on this page is read-only because \
editing hand-written Nix by machine eats comments and rearranges structure. \
A wholly generated file cannot be mangled: nothing is preserved across the \
write. That is why these are editable and the rest are not - not because \
they matter less."
                ifWrong: "<ul>\
<li><b>Nothing changed after setting a value.</b> Expected. The file is Nix \
source; it takes effect at the next rebuild. An <i>Apply</i> action appears \
below when a declared value differs from the running one.</li>\
<li><b>A value snaps back.</b> The engine refused it - the reason appears in \
red. Ports below 1024 are refused outright.</li>\
<li><b>The port changed but the window went red.</b> The rebuild moved the \
declared port; the service keeps the old one until restarted.</li></ul>"
                sections: [
                    { title: "Declared vs in effect", body: "\
Two genuinely different facts, which is why both are shown.<br><br>\
<b>Declared</b> is what the Nix file says. Writing it is instant and \
harmless.<br>\
<b>In effect</b> is what the running service is actually using - its \
environment, fixed when it started.<br><br>\
They diverge the moment you change something, and converge again after \
<tt>home-manager switch</tt> plus a restart. A tool that hid that gap would \
have to pretend a declarative system has live settings, which is the lie \
this whole page is built to avoid.<br><br>\
Only <i>port</i> and <i>log level</i> have a running counterpart. The two \
autostart flags take effect at the next login, so there is nothing to \
compare them against and no pending marker is shown for them." },
                    { title: "What applies a change", body: "\
<b>1. <tt>home-manager switch</tt></b> - rebuilds your user environment from \
the Nix files. No root: this is your own configuration, so there is no \
polkit prompt. It rebuilds <i>everything</i> home-manager manages, so an \
unrelated half-finished edit elsewhere will also be applied, or will fail the \
build and leave the current generation untouched.<br><br>\
<b>2. <tt>systemctl --user restart nixdash-engine.service</tt></b> - a \
changed user service keeps running the old build until restarted. Your \
<tt>home.nix</tt> sets <tt>startServices = \"suggest\"</tt>, so home-manager \
prints the command rather than running it - restarting services \
automatically takes xfconf down and kills the Xfce panel on this \
machine.<br><br>\
The Apply action runs step 1 only. Step 2 is deliberately separate: the \
switch may fail, and restarting into a build that did not happen is worse \
than leaving the working one running." }
                ]
            }
            Item { Layout.fillWidth: true }
            Label {
                visible: root.anyPending
                text: "changes not applied"
                font.pixelSize: 10
                color: style.pendingText
                padding: 3
                background: Rectangle { color: style.pendingTint; radius: 3 }
            }
        }

        Label {
            Layout.fillWidth: true
            text: root.filePath === "" ? "" : "written to " + root.filePath
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
            model: root.settings

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    text: modelData.label
                    font.pixelSize: 12
                    Layout.preferredWidth: 190
                }

                // [label] [control] [info] - the control beside its label,
                // the info button trailing the thing it explains.
                //
                // One control per kind. SpinBox rather than a free text field
                // so an out-of-range port is awkward to even express - the
                // engine still validates, but the UI should not invite a
                // value it knows will be refused.
                Loader {
                    Layout.preferredWidth: 150
                    sourceComponent: modelData.kind === "bool" ? boolControl
                                   : modelData.kind === "port" ? portControl
                                   : enumControl
                    property var setting: modelData
                }

                InfoButton {
                    Layout.alignment: Qt.AlignVCenter
                    title: modelData.label
                    what: modelData.what
                    why: modelData.why
                    ifWrong: modelData.if_wrong
                }

                // Says "saving" in words. Controls are never greyed out to
                // mean busy: a disabled control reads as broken, and there is
                // nothing to guard - each write sends an explicit value, so a
                // second one simply lands on whatever you chose last.
                Label {
                    visible: root.busy[modelData.key] === true
                             || root.pending(modelData)
                    text: {
                        if (root.busy[modelData.key] === true)
                            return "saving…"
                        if (modelData.key === "port")
                            return "running: " + root.effective.port
                        return "running: " + String(root.effective.logLevel || "")
                    }
                    font.pixelSize: 10
                    color: style.pendingText
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Item {
                    Layout.fillWidth: !(root.busy[modelData.key] === true
                                        || root.pending(modelData))
                }
            }
        }
    }

    Component {
        id: boolControl
        Switch {
            checked: setting.declared === true
            // onToggled, not onCheckedChanged: the latter also fires when the
            // binding updates after a reload, which would write back the
            // value we just read and loop.
            onToggled: root.write(setting.key, checked)
        }
    }

    Component {
        id: portControl
        SpinBox {
            from: setting.min !== undefined ? setting.min : 1024
            to: setting.max !== undefined ? setting.max : 65535
            value: setting.declared !== null ? setting.declared : 3100
            editable: true
            // SpinBox groups digits by locale, which renders port 3100 as
            // "3,100". A port is an identifier, not a quantity - no separator
            // belongs in it, and one invites typing it back in with a comma.
            textFromValue: function(value, locale) { return String(value) }
            valueFromText: function(text, locale) {
                return parseInt(text.replace(/[^0-9]/g, ""), 10)
            }
            // Written on commit rather than on every increment: holding the
            // up arrow would otherwise rewrite the file dozens of times.
            onValueModified: root.write(setting.key, value)
        }
    }

    Component {
        id: enumControl
        ComboBox {
            model: setting.options
            currentIndex: Math.max(0, setting.options.indexOf(setting.declared))
            onActivated: root.write(setting.key, setting.options[currentIndex])
        }
    }
}
