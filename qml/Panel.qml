import QtQuick
import QtQuick.Controls

// Shared frame for every panel: status dot, title, subtitle, an info button,
// and a slot for content. Panels differ in what they show, not in how they
// are framed or explained.
//
// Given a `summary` straight from GET /api/panels, everything in the header
// comes from the engine - including the severity. Panels used to compute
// their own thresholds in QML, which duplicated judgement that belongs next
// to the code producing the numbers.
Rectangle {
    id: root

    Style { id: style }

    /// A PanelSummary from the engine. Optional: a panel can still be driven
    /// by explicit title/subtitle/state_ if it has no summary.
    property var summary: null

    property string title: summary ? summary.title : ""
    property string subtitle: summary ? summary.headline : ""
    // "ok" | "warn" | "bad" | "stale"
    property string state_: !summary ? "stale"
                          : summary.status === "unknown" ? "stale"
                          : summary.status

    default property alias content: body.data

    readonly property var value: summary && summary.latest ? summary.latest.value : null

    /// Look up the engine's explanation for one field, for StatRow.
    function infoFor(key) {
        if (!summary || !summary.stats)
            return null
        var m = summary.stats.filter(function(s) { return s.key === key })
        return m.length > 0 ? m[0] : null
    }

    implicitHeight: 190
    radius: 8
    color: palette.base
    border.color: palette.mid

    readonly property var stateColors: ({
        "ok":    style.okDot,
        "warn":  style.warnDot,
        "bad":   style.badDot,
        "stale": style.unknownDot
    })

    Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        Row {
            width: parent.width
            spacing: 8

            Rectangle {
                width: 10; height: 10; radius: 5
                anchors.verticalCenter: parent.verticalCenter
                color: root.stateColors[root.state_] || style.unknownDot
            }

            Label {
                text: root.title
                font.pixelSize: 15
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }

            Label {
                text: root.subtitle
                font.pixelSize: 12
                opacity: 0.6
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - x - 24)
                elide: Text.ElideRight
            }

            // The header button sits at the right edge, deliberately outside
            // the stat-button column below it.
            InfoButton {
                anchors.verticalCenter: parent.verticalCenter
                title: root.title
                what: root.summary && root.summary.info ? root.summary.info.what : ""
                why: root.summary && root.summary.info ? root.summary.info.why : ""
                ifWrong: root.summary && root.summary.info ? root.summary.info.if_wrong : ""
            }
        }

        Item {
            id: body
            width: parent.width
            height: parent.height - y
        }
    }
}
