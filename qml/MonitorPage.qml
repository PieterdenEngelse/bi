import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The overview: one card per subject, and anything urgent promoted above them.
//
// A grid of every panel gives them all equal weight, so "Qt prefix complete"
// and "disk at 92%" look the same until you read both. This page exists so
// that most of the time you read nothing.
Item {
    id: root

    property var panels: []
    property var actions: []

    signal openSubject(string subject)

    readonly property var subjects: [
        { key: "nixos", name: "NixOS" },
        { key: "qt",    name: "Qt" },
        { key: "rust",  name: "Rust" }
    ]

    readonly property var statusColors: ({
        "ok":      "#4caf50",
        "warn":    "#ff9800",
        "bad":     "#f44336",
        "unknown": "#9e9e9e"
    })
    // Worst-first, so a subject's dot reflects its unhappiest panel rather
    // than an average that hides it.
    readonly property var statusRank: ({ "bad": 0, "warn": 1, "unknown": 2, "ok": 3 })

    function panelsOf(key) {
        return panels.filter(function(p) { return p.subject === key })
    }
    function actionsOf(key) {
        return actions.filter(function(a) { return a.subject === key })
    }
    // Explicit loop rather than sort-with-closure: the comparator form
    // depended on `statusRank` resolving through the scope chain inside a
    // nested function, which it did not do reliably - the card showed warn
    // while every panel reported ok.
    function rankOf(s) {
        if (s === "bad") return 0
        if (s === "warn") return 1
        if (s === "unknown") return 2
        if (s === "ok") return 3
        return 2
    }
    function worstOf(key) {
        var ps = panelsOf(key)
        if (ps.length === 0)
            return "unknown"
        var worst = ps[0].status
        for (var i = 1; i < ps.length; ++i)
            if (rankOf(ps[i].status) < rankOf(worst))
                worst = ps[i].status
        return worst
    }
    function headlineOf(key) {
        var ps = panelsOf(key)
        if (ps.length === 0)
            return "no panels"
        // Worst first: the interesting one leads.
        var sorted = ps.slice()
        sorted.sort(function(a, b) { return root.rankOf(a.status) - root.rankOf(b.status) })
        var out = []
        for (var i = 0; i < sorted.length; ++i)
            out.push(sorted[i].headline)
        return out.join("  ·  ")
    }

    readonly property var urgent: actions.filter(function(a) {
        return a.urgency === "needed"
    })

    ScrollView {
        anchors.fill: parent
        anchors.margins: 14
        contentWidth: availableWidth

        Column {
            // Capped and centred rather than full-bleed. Maximised on a wide
            // display these cards stretch into thin bars with the headline
            // pinned far left and the action count far right, a screen's
            // width apart - two things you must read together, placed as far
            // apart as the hardware allows. A measure is what makes them
            // scannable; the empty margin is doing work.
            width: Math.min(parent.width, 1100)
            x: (parent.width - width) / 2
            spacing: 12

            // Urgent actions sit above the cards: a failed unit should not be
            // something you find by clicking into a subject.
            Repeater {
                model: root.urgent
                Rectangle {
                    width: parent.width
                    height: 44
                    radius: 6
                    color: "#fdecea"
                    border.color: "#f44336"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        Rectangle { width: 8; height: 8; radius: 4; color: "#f44336" }
                        Label {
                            text: modelData.title
                            font.bold: true
                            font.pixelSize: 13
                            color: "#5f2120"
                        }
                        Label {
                            Layout.fillWidth: true
                            text: modelData.why
                            font.pixelSize: 11
                            color: "#5f2120"
                            opacity: 0.8
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            Repeater {
                model: root.subjects

                Rectangle {
                    width: parent.width
                    height: 86
                    radius: 8
                    color: hover.hovered ? palette.alternateBase : palette.base
                    border.color: palette.mid

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openSubject(modelData.key)
                        property bool hovered: containsMouse
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 14

                        Rectangle {
                            width: 12; height: 12; radius: 6
                            Layout.alignment: Qt.AlignVCenter
                            color: root.statusColors[root.worstOf(modelData.key)] || "#9e9e9e"
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Label {
                                text: modelData.name
                                font.bold: true
                                font.pixelSize: 16
                            }
                            Label {
                                Layout.fillWidth: true
                                text: root.headlineOf(modelData.key)
                                font.pixelSize: 12
                                opacity: 0.7
                                elide: Text.ElideRight
                            }
                        }

                        Label {
                            text: {
                                var n = root.actionsOf(modelData.key).length
                                return n === 0 ? "—" : n + (n === 1 ? " action" : " actions")
                            }
                            font.pixelSize: 12
                            opacity: 0.6
                        }

                        // The dot's rule is not visible from the dot. Sits
                        // before the chevron so it does not read as part of
                        // the "open this subject" affordance.
                        InfoButton {
                            Layout.alignment: Qt.AlignVCenter
                            title: modelData.name + " card"
                            what: "One row per subject. The dot is that \
subject's <b>worst</b> panel - not an average, not a count. One bad panel \
among four still shows red. The line beside it lists every panel's headline, \
worst first, and the count on the right is how many actions that subject is \
currently offering."
                            why: "Averaging would let a full disk hide behind \
three healthy panels, which is the one thing a dashboard must never do. \
Clicking the row opens that subject's panels, where every number carries its \
own explanation."
                            ifWrong: "<ul>\
<li><b>A grey dot means 'could not look', not 'fine'.</b> The engine failed \
to read something, which is different from finding nothing wrong.</li>\
<li><b>Red with a reassuring headline.</b> The headline is worst-first, but \
it is one line - open the subject to see the panel that is actually \
unhappy.</li>\
<li><b>Nothing here at all.</b> If every card is grey and the address in the \
header is red, the window is not reaching the engine.</li></ul>"
                            sections: [
                                { title: "The colours", body: "\
<table cellpadding='5'>\
<tr><td><b>Green</b> - ok</td><td>Nothing to do. Most of the time every card \
should be this, which is the point of the page.</td></tr>\
<tr><td><b>Amber</b> - warn</td><td>Drifting, and worth dealing with at a \
time of your choosing. A disk past 85%, or a toolchain missing a target you \
are not currently building for.</td></tr>\
<tr><td><b>Red</b> - bad</td><td>Wrong now. A failed unit, a disk past 93%, a \
Qt prefix that will break the next build.</td></tr>\
<tr><td><b>Grey</b> - unknown</td><td>The engine could not measure it. \
Deliberately <i>not</i> green: 'no failures found' and 'I could not look' are \
different answers, and conflating them is how a monitor reassures you about \
something it never checked.</td></tr>\
</table><br>\
The thresholds live in the engine, with the panel that owns them, so both \
this window and the browser build show the same verdict. Each panel's own \
info button gives its exact numbers." },
                                { title: "What gets promoted", body: "\
Anything at <b>needed</b> urgency is lifted out of these cards and shown \
above them, in red, regardless of subject.<br><br>\
A failed unit should not be something you find by clicking into NixOS. The \
cards are for the healthy case; the strip above them is for the case where \
you should stop reading and act.<br><br>\
Actions carry one of three urgencies:<ul>\
<li><b>needed</b> - something is wrong now. Promoted.</li>\
<li><b>advised</b> - drifting; worth doing soon. Config edited but never \
rebuilt, for instance.</li>\
<li><b>routine</b> - offered, never nagged. Garbage collection is always \
available and almost never urgent.</li></ul>\
Sorting is by urgency, so routine maintenance can never push a real problem \
down the list." }
                            ]
                        }

                        Label { text: "›"; font.pixelSize: 20; opacity: 0.4 }
                    }
                }
            }

            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: 10
                text: root.panels.length === 0 ? "waiting for the engine…" : ""
                opacity: 0.5
                font.pixelSize: 12
            }
        }
    }
}
