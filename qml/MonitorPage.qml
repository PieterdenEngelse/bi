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
