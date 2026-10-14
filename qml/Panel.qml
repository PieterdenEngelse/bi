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

    /// Opt-in content-driven height. Left at 0 a panel keeps the old fixed
    /// 190, which FailedUnitsPanel and GenerationsPanel rely on: their bodies
    /// are `height: parent.height`, so deriving the frame's height from them
    /// would be circular. Panels whose content is intrinsically sized set this
    /// to their content item's implicitHeight instead, rather than the frame
    /// guessing a constant - 190 clipped MemoryPanel's fourth stat row.
    property real contentHeight: 0

    implicitHeight: contentHeight > 0 ? 14 + body.y + contentHeight + 14 : 190
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

        // The header button is anchored to the right edge rather than being
        // the last child of the Row. As a Row child it was placed after the
        // subtitle's reserved width plus the Row's 8px spacing, landing 8px
        // further right than every StatRow button below it - a one-button
        // ragged edge down the side of each panel. Anchoring both to the same
        // right edge is what puts them in one column.
        Item {
            id: header
            width: parent.width
            height: Math.max(headerRow.implicitHeight, headerInfo.height)

            Row {
                id: headerRow
                anchors.left: parent.left
                anchors.right: headerInfo.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
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
                    width: Math.max(0, headerRow.width - x)
                    elide: Text.ElideRight
                }
            }

            InfoButton {
                id: headerInfo
                anchors.right: parent.right
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
            height: root.contentHeight > 0 ? root.contentHeight : parent.height - y
        }
    }
}
