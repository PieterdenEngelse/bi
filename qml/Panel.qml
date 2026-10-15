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

    /// Look up the engine's explanation for one field, for StatBlock.
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

    /// Formats one engine value for display. Lives here rather than in
    /// GenericPanel because the header's Copy needs exactly the same
    /// formatting, and two implementations would drift.
    function renderValue(v) {
        if (v === null || v === undefined)
            return "—"
        // Not Array.isArray: a JSON array reaching QML through a `var`
        // property arrives as a QVariantList, which fails that check and
        // would fall through to JSON.stringify. Duck-type instead.
        if (typeof v === "object" && typeof v.length === "number")
            return v.length === 0 ? "none" : Array.prototype.join.call(v, ", ")
        if (typeof v === "boolean")
            return v ? "yes" : "no"
        if (typeof v === "object")
            return JSON.stringify(v)
        return String(v)
    }

    /// Lines appended to panelText() by panels whose content is a list
    /// rather than readings - the units and the generations. Without it the
    /// Copy on those two panels would hand back a header and nothing else.
    property string extraText: ""

    /// The whole pane as plain text: title, headline, then one line per stat.
    /// A selection cannot cross from one text item into the next - Qt shares
    /// a selection only within a single item - and the rows cannot be merged
    /// into one item without losing the per-stat info buttons. So taking the
    /// whole pane is a button rather than a drag.
    function panelText() {
        var out = root.title + "\n" + root.subtitle + "\n"
        var stats = root.summary && root.summary.stats ? root.summary.stats : []
        for (var i = 0; i < stats.length; i++) {
            var k = stats[i].key
            out += k + "\t" + root.renderValue(root.value ? root.value[k] : null) + "\n"
        }
        return out + root.extraText
    }

    Clipboard { id: clip }

    // Ctrl+Shift+C copies this whole pane, but only while the pointer is over
    // it. Scoping it to hover is what keeps one shortcut unambiguous across
    // a dozen panels: exactly one can be hovered, so exactly one of these is
    // ever enabled, and with none hovered the window's own copy takes over
    // and hands back the whole page.
    HoverHandler { id: paneHover }
    Shortcut {
        sequences: [ "Ctrl+Shift+C" ]
        enabled: paneHover.hovered
        onActivated: clip.put(root.panelText())
    }

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
        // further right than every StatBlock button below it - a one-button
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

                SelectableText {
                    text: root.title
                    font.pixelSize: 15
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }

                // The headline is the sentence you quote when reporting
                // something, so it is selectable. Wrapping, not elided:
                // TextEdit has no elide, and a headline cut short is the
                // half you cannot paste.
                SelectableText {
                    text: root.subtitle
                    font.pixelSize: style.fontBody
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, headerRow.width - x)
                    wrapMode: TextEdit.Wrap
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
