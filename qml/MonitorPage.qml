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

    Style { id: style }

    property var panels: []
    property var actions: []

    signal openSubject(string subject)

    readonly property var subjects: [
        { key: "nixos", name: "NixOS" },
        { key: "qt",    name: "Qt" },
        { key: "rust",  name: "Rust" }
    ]

    readonly property var statusColors: ({
        "ok":      style.okDot,
        "warn":    style.warnDot,
        "bad":     style.badDot,
        "unknown": style.unknownDot
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
            // Full width. This was capped at 1100 and centred, on the argument
            // that a maximised window stretches each card into a thin bar with
            // the headline pinned far left and the action count far right.
            // That reasoning stands, but the window is the user's to fill and
            // the empty margin read as wasted space - so the cap is gone.
            width: parent.width
            spacing: 12

            // Urgent actions sit above the cards: a failed unit should not be
            // something you find by clicking into a subject.
            Repeater {
                model: root.urgent
                Rectangle {
                    width: parent.width
                    height: 52
                    radius: 6
                    color: style.badTint
                    border.color: style.badDot

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        Rectangle { width: 10; height: 10; radius: 5; color: style.badDot }
                        SelectableText {
                            text: modelData.title
                            font.bold: true
                            font.pixelSize: 15
                            color: style.badText
                        }
                        // Was 11px at opacity 0.8. The colour was never the
                        // problem - #fca5a5 on #3a1d1e is about 7.9:1 - but
                        // screen-scale.nix downscales a 120% framebuffer, so
                        // 11px renders smaller than 11px, and the dimming took
                        // the contrast down to ~5.7:1 on top of that. This is
                        // the one strip that exists to be read from across the
                        // room, so it gets full opacity and a readable size.
                        SelectableText {
                            Layout.fillWidth: true
                            text: modelData.why
                            font.pixelSize: 13
                            color: style.badText
                            wrapMode: TextEdit.NoWrap
                            clip: true
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

                    // Handlers, not a MouseArea: a TapHandler on its default
                    // DragThreshold policy takes only a PASSIVE grab, so the
                    // selectable text below still receives the moves that
                    // extend a selection - and a drag past the threshold
                    // cancels the tap, so selecting text does not also
                    // navigate. A click still opens the subject.
                    HoverHandler {
                        id: hover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: root.openSubject(modelData.key)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 14

                        Rectangle {
                            width: 12; height: 12; radius: 6
                            Layout.alignment: Qt.AlignVCenter
                            color: root.statusColors[root.worstOf(modelData.key)] || style.unknownDot
                        }

                        // Name and headline in ONE text item, not two
                        // stacked ones: a drag selects only inside the item
                        // it started in, so two items meant the card's text
                        // could never be taken in one go. Muted by colour
                        // rather than opacity - rich text has no per-span
                        // opacity. Clipped rather than elided (TextEdit has
                        // no elide); the card is a fixed 86px, so the
                        // headline keeps to its one line.
                        SelectableText {
                            id: cardText
                            Layout.fillWidth: true
                            textFormat: TextEdit.RichText
                            wrapMode: TextEdit.NoWrap
                            clip: true
                            text: "<div><span style='font-size:16px; "
                                + "font-weight:bold'>"
                                + cardText.esc(modelData.name)
                                + "</span></div><div><span "
                                + "style='font-size:12px; color:"
                                + style.textMuted + "'>"
                                + cardText.esc(root.headlineOf(modelData.key))
                                + "</span></div>"
                        }

                        SelectableText {
                            text: {
                                var n = root.actionsOf(modelData.key).length
                                return n === 0 ? "—" : n + (n === 1 ? " action" : " actions")
                            }
                            font.pixelSize: 12
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
<ul>\
<li><b>Green</b> - ok. Nothing to do. Most of the time every card should be \
this, which is the point of the page.</li>\
<li><b>Amber</b> - warn. Drifting, and worth dealing with at a time of your \
choosing. A disk past 85%, or a toolchain missing a target you are not \
currently building for.</li>\
<li><b>Red</b> - bad. Wrong now. A failed unit, a disk past 93%, a Qt prefix \
that will break the next build.</li>\
<li><b>Grey</b> - unknown. It could not be measured. Deliberately <i>not</i> \
green: 'no failures found' and 'I could not look' are different answers, and \
conflating them is how a monitor reassures you about something it never \
checked.</li>\
</ul><br>\
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

                        Label { text: "›"; font.pixelSize: 20 }
                    }
                }
            }

            SelectableText {
                width: parent.width
                horizontalAlignment: TextEdit.AlignHCenter
                topPadding: 10
                text: root.panels.length === 0 ? "waiting for the engine…" : ""
                font.pixelSize: 12
            }
        }
    }
}
