import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Prepared commands, with the option to run them.
//
// Two things are kept apart here on purpose. The monospace block is the
// command as *prose* - multi-line, commented, often leading with a dry-run you
// should look at first. The Run button executes the engine's `run` spec
// instead: one program, one argument list, shown in the confirmation dialog
// before anything happens. They are not the same text, and the dialog is where
// that becomes visible rather than surprising.
//
// Actions with no `run` (Nix snippets) keep Copy alone - there is nothing to
// execute, and offering a disabled Run would imply there was.
Panel {
    id: root

    property var actions: []
    property var errors: []
    // This panel posts directly rather than routing through Main's getJson.
    // Fetching lives in Main because it is shared polling; a run is a local,
    // one-off consequence of a button in this panel, and its result belongs
    // next to the button that caused it.
    property string apiBase: ""

    // Emitted after a run finishes, so the shell can re-poll: most actions
    // change exactly the state the panels are displaying.
    signal ranAction()

    // id -> { running: bool, ok: bool, text: string }
    property var results: ({})

    function setResult(id, value) {
        var next = {}
        for (var k in root.results)
            next[k] = root.results[k]
        next[id] = value
        root.results = next     // reassign: mutating in place updates nothing
    }
    function resultFor(id) {
        return root.results[id] || null
    }

    // What will actually be executed, as a single readable line. This is the
    // engine's run spec, NOT the displayed command.
    function argvLine(run) {
        if (!run)
            return ""
        var parts = [run.program]
        for (var i = 0; i < run.args.length; ++i) {
            var a = run.args[i]
            // Quote anything that would be ambiguous when read back, so the
            // dialog cannot imply word-splitting that will not happen.
            parts.push(a.indexOf(" ") >= 0 ? JSON.stringify(a) : a)
        }
        var line = parts.join(" ")
        return run.elevate ? "pkexec " + line : line
    }

    function startRun(action) {
        root.setResult(action.id, { running: true, ok: false, text: "" })

        var xhr = new XMLHttpRequest()
        xhr.open("POST", root.apiBase + "/api/actions/" + encodeURIComponent(action.id) + "/run")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            var ok = false
            var text = ""
            try {
                var d = JSON.parse(xhr.responseText)
                if (xhr.status === 200) {
                    ok = d.ok
                    var o = d.outcome
                    // Report the failure reason, not just "it failed".
                    text = o.error ? o.error
                         : ok ? (o.stdout || "done")
                         : "exit " + o.exit_code + (o.stderr ? ": " + o.stderr : "")
                } else {
                    text = d.error || ("HTTP " + xhr.status)
                }
            } catch (e) {
                text = xhr.status === 0
                    ? "engine unreachable"
                    : "HTTP " + xhr.status
            }
            root.setResult(action.id, { running: false, ok: ok, text: text })
            root.ranAction()
        }
        xhr.send()
    }

    // One dialog, reused. The confirmation is the last point at which the
    // consequences are still only text, so it carries the effects and the
    // "if wrong" note rather than a bare are-you-sure.
    Dialog {
        id: confirm
        property var action: null

        anchors.centerIn: parent
        width: Math.min(root.width - 40, 560)
        modal: true
        title: confirm.action ? confirm.action.title : ""
        standardButtons: Dialog.Cancel | Dialog.Ok

        onAccepted: if (confirm.action) root.startRun(confirm.action)

        contentItem: Column {
            spacing: 9

            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                font.pixelSize: 11
                opacity: 0.8
                text: "This will execute, as written:"
            }

            Rectangle {
                width: parent.width
                height: argv.implicitHeight + 12
                radius: 4
                color: palette.alternateBase
                border.color: palette.mid
                Label {
                    id: argv
                    x: 7; y: 6
                    width: parent.width - 14
                    text: root.argvLine(confirm.action ? confirm.action.run : null)
                    font.family: "monospace"
                    font.pixelSize: 11
                    wrapMode: Text.WrapAnywhere
                }
            }

            // Why this is not simply the command shown in the panel.
            Label {
                width: parent.width
                visible: confirm.action
                         && confirm.action.command.indexOf("\n") >= 0
                wrapMode: Text.WordWrap
                font.pixelSize: 10
                opacity: 0.6
                text: "The block in the panel also lists an inspection or \
dry-run step. Only the line above runs."
            }

            Label {
                width: parent.width
                visible: confirm.action && confirm.action.needs_root
                wrapMode: Text.WordWrap
                font.pixelSize: 11
                text: "Needs root. polkit will ask you to authenticate - \
nixdash has no privilege of its own, so that prompt is what permits it."
            }

            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                font.pixelSize: 11
                text: confirm.action
                      ? "Effects:\n  · " + confirm.action.effects.join("\n  · ")
                      : ""
            }

            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                font.pixelSize: 10
                opacity: 0.7
                text: confirm.action && confirm.action.info
                      ? confirm.action.info.if_wrong : ""
            }
        }
    }

    readonly property int needed: actions.filter(function(a) { return a.urgency === "needed" }).length

    readonly property var urgencyColors: ({
        "needed":  "#f44336",
        "advised": "#ff9800",
        "routine": "#9e9e9e"
    })

    title: "Suggested actions"
    subtitle: errors.length > 0
              ? errors.length + " probe(s) failed"
              : actions.length === 0 ? "nothing to do"
              : actions.length + " suggested" + (needed > 0 ? ", " + needed + " needed" : "")
    state_: errors.length > 0 ? "stale"
          : needed > 0 ? "bad"
          : actions.length > 0 ? "warn"
          : "ok"

    // Off-screen helper: QML has no clipboard API, but TextEdit.copy() works
    // on both desktop and wasm (a button press is the user gesture the
    // browser requires).
    TextEdit {
        id: clip
        visible: false
        readOnly: true
    }
    function copyToClipboard(text) {
        clip.text = text
        clip.selectAll()
        clip.copy()
        clip.deselect()
    }

    ScrollView {
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth

        Column {
            width: parent.width
            spacing: 10

            Repeater {
                model: root.actions

                Rectangle {
                    width: parent.width
                    height: col.implicitHeight + 18
                    radius: 6
                    color: "transparent"
                    border.color: palette.mid

                    Column {
                        id: col
                        x: 10
                        y: 9
                        width: parent.width - 20
                        spacing: 5

                        Row {
                            spacing: 7
                            width: parent.width

                            Rectangle {
                                width: 8; height: 8; radius: 4
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.urgencyColors[modelData.urgency] || "#9e9e9e"
                            }
                            Label {
                                text: modelData.title
                                font.bold: true
                                font.pixelSize: 13
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            // Mechanism and risk: what a bare command line
                            // cannot tell you.
                            InfoButton {
                                anchors.verticalCenter: parent.verticalCenter
                                title: modelData.title
                                what: modelData.info ? modelData.info.what : ""
                                why: modelData.why
                                ifWrong: modelData.info ? modelData.info.if_wrong : ""
                            }
                            // Shell vs Nix: "run this" and "paste this into a
                            // file, then rebuild" are different instructions,
                            // and labelling a flake fragment as a command to
                            // run would be nonsense.
                            Rectangle {
                                width: kindLbl.implicitWidth + 10
                                height: kindLbl.implicitHeight + 3
                                radius: 3
                                color: modelData.kind === "nix" ? "#e3f2fd" : "#eceff1"
                                anchors.verticalCenter: parent.verticalCenter
                                Label {
                                    id: kindLbl
                                    anchors.centerIn: parent
                                    text: modelData.kind === "nix"
                                          ? "paste into your Nix config"
                                          : "run in a terminal"
                                    font.pixelSize: 10
                                    color: modelData.kind === "nix" ? "#0d47a1" : "#37474f"
                                }
                            }
                            Rectangle {
                                visible: modelData.needs_root
                                width: rootLbl.implicitWidth + 10
                                height: rootLbl.implicitHeight + 3
                                radius: 3
                                color: "#ffecb3"
                                anchors.verticalCenter: parent.verticalCenter
                                Label {
                                    id: rootLbl
                                    anchors.centerIn: parent
                                    text: "needs root"
                                    font.pixelSize: 10
                                    color: "#5d4037"
                                }
                            }
                        }

                        Label {
                            width: parent.width
                            text: modelData.why
                            font.pixelSize: 11
                            opacity: 0.75
                            wrapMode: Text.WordWrap
                        }

                        // The command. Selectable so it can be copied by hand
                        // too - the button is a convenience, not the only way.
                        Rectangle {
                            width: parent.width
                            height: cmd.implicitHeight + 12
                            radius: 4
                            color: palette.alternateBase
                            border.color: palette.mid

                            TextEdit {
                                id: cmd
                                x: 7; y: 6
                                width: parent.width - 14
                                text: modelData.command
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.Wrap
                                font.family: "monospace"
                                font.pixelSize: 11
                                color: palette.text
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 8

                            Button {
                                text: "Copy"
                                onClicked: root.copyToClipboard(modelData.command)
                            }
                            // Absent, not disabled, when there is nothing to
                            // execute: a greyed-out Run would suggest the
                            // snippet is runnable and something is stopping it.
                            Button {
                                visible: !!modelData.run
                                enabled: {
                                    var r = root.resultFor(modelData.id)
                                    return !(r && r.running)
                                }
                                text: {
                                    var r = root.resultFor(modelData.id)
                                    if (r && r.running)
                                        return "Running…"
                                    return modelData.needs_root ? "Run (asks for root)" : "Run"
                                }
                                onClicked: {
                                    confirm.action = modelData
                                    confirm.open()
                                }
                            }
                            // The control that changes your machine gets its
                            // own explanation, separate from the action's.
                            // The action's info says what the command does;
                            // this says what pressing the button does, which
                            // is a different question and the one people get
                            // wrong - above all that it does not run the text
                            // in the box.
                            InfoButton {
                                visible: !!modelData.run
                                anchors.verticalCenter: parent.verticalCenter
                                title: "Run"
                                what: "Sends this action's id to the engine, \
which then runs its own fixed program and argument list - the exact line shown \
in the confirmation dialog. It does NOT run the text in the box above: that is \
written for a person to read, and often lists an inspection or dry-run step \
before the real command."
                                why: "The engine holds no privilege of its \
own. Anything needing root goes through pkexec, so polkit raises a prompt and \
that prompt is what authorises it - not nixdash. Dismiss it and nothing \
happens. The engine cannot be asked to run anything other than the actions it \
is offering."
                                ifWrong: "If nothing seems to happen, the \
polkit prompt was most likely dismissed, or no authentication agent is running \
in this session. Note also that the command runs in the *engine's* environment \
- the systemd user service's - not your shell's, so PATH and any Qt or Rust \
toolchain differ from what a terminal would give you."
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.effects.join("  ·  ")
                                font.pixelSize: 10
                                opacity: 0.6
                                elide: Text.ElideRight
                                width: Math.max(0, parent.width - 230)
                            }
                        }

                        // Outcome of the last run of this action: exit status,
                        // or the reason it could not start. Shown rather than
                        // logged, because a privileged action that quietly did
                        // nothing is the worst case.
                        Rectangle {
                            property var res: root.resultFor(modelData.id)
                            visible: res && !res.running && res.text !== ""
                            width: parent.width
                            height: resLbl.implicitHeight + 12
                            radius: 4
                            color: res && res.ok ? "#e8f5e9" : "#fdecea"
                            border.color: res && res.ok ? "#4caf50" : "#f44336"

                            Label {
                                id: resLbl
                                x: 7; y: 6
                                width: parent.width - 14
                                text: parent.res
                                      ? (parent.res.ok ? "✓ " : "✗ ") + parent.res.text
                                      : ""
                                color: parent.res && parent.res.ok ? "#1b5e20" : "#5f2120"
                                font.family: "monospace"
                                font.pixelSize: 10
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }

            Label {
                visible: root.actions.length === 0 && root.errors.length === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: 20
                text: "Nothing needs doing."
                opacity: 0.5
            }

            Repeater {
                model: root.errors
                Label {
                    width: parent.width
                    text: "probe " + modelData.provider + " failed: " + modelData.error
                    color: "#ff9800"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
