import QtQuick
import QtQuick.Controls

Panel {
    id: root

    Style { id: style }

    /// [{at, value}] oldest first, for the sparkline.
    property var history: []

    readonly property real availableGb: value ? value.available_kb / 1048576 : 0
    readonly property real totalGb:     value ? value.total_kb / 1048576 : 0
    readonly property real usedPct:     value ? value.used_fraction * 100 : 0
    readonly property real swapFreeGb:  value ? value.swap_free_kb / 1048576 : 0
    readonly property real pressure60:  value && value.pressure_some_avg60 !== undefined
                                        ? value.pressure_some_avg60 : 0

    // title, subtitle and state_ come from the engine via Panel.

    // 64px sparkline plus four stat rows does not fit the frame's default
    // 190, which is what clipped "stall 60s" off the bottom.
    contentHeight: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: 6

        Canvas {
            id: spark
            width: parent.width
            height: 64

            property var pts: root.history
            onPtsChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var n = pts.length
                if (n < 2)
                    return

                // Fixed 0..100% scale: an autoscaled memory graph always looks
                // dramatic and hides the only thing that matters, which is
                // distance from the ceiling.
                function xy(i) {
                    var v = pts[i].value
                    var used = v.used_fraction !== undefined ? v.used_fraction : 0
                    return [ i / (n - 1) * width, height - used * height ]
                }

                ctx.beginPath()
                var p0 = xy(0)
                ctx.moveTo(p0[0], p0[1])
                for (var i = 1; i < n; ++i) {
                    var p = xy(i)
                    ctx.lineTo(p[0], p[1])
                }
                ctx.strokeStyle = root.stateColors[root.state_] || style.unknownDot
                ctx.lineWidth = 2
                ctx.stroke()

                ctx.lineTo(width, height)
                ctx.lineTo(0, height)
                ctx.closePath()
                ctx.globalAlpha = 0.12
                ctx.fillStyle = ctx.strokeStyle
                ctx.fill()
            }
        }

        StatRow {
            label: "available"
            value: root.value ? root.availableGb.toFixed(1) + " GB of " + root.totalGb.toFixed(1) : "—"
            panel: root
            statKey: "available_kb"
        }
        StatRow {
            label: "used"
            value: root.value ? root.usedPct.toFixed(0) + "%" : "—"
            panel: root
            statKey: "used_fraction"
        }
        StatRow {
            label: "swap free"
            value: root.value ? root.swapFreeGb.toFixed(1) + " GB" : "—"
            panel: root
            statKey: "swap_free_kb"
        }
        StatRow {
            label: "stall 60s"
            value: root.value ? root.pressure60.toFixed(2) + "%" : "—"
            panel: root
            statKey: "pressure_some_avg60"
        }
    }
}
