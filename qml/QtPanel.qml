import QtQuick
import QtQuick.Controls

// Qt, judged by whether a cxx-qt build would work here.
//
// A key/value list would report "Qt 6.11.2" and look fine while the prefix is
// missing two of the four host tools cxx-qt needs - which is exactly the state
// that builds happily until code generation and then fails naming a tool
// rather than the cause. So the panel leads with the verdict and shows the
// tool checklist, because that is the thing you would otherwise find out the
// slow way.
Panel {
    id: root

    Style { id: style }

    // Header + verdict + 3 rows + gap + 4 tool rows. Panel's 190 default
    // clipped the last two tools, which are the two that matter most.
    // Content-driven: a wrapped prefix or target spec makes the block taller
    // than a fixed height can allow for.
    contentHeight: col.implicitHeight

    readonly property bool present: value && value.version
    readonly property bool complete: value ? value.prefix_complete : false
    readonly property var missing: value && value.tools_missing ? value.tools_missing : []
    readonly property var found: value && value.tools_found ? value.tools_found : []

    // Says "no qmake", never "no Qt". This panel looked for a build tool on
    // PATH and found none; that says nothing about whether Qt is present, and
    // the Qt runtime panel beside it usually proves it is. See
    // headlines_claim_only_what_was_measured in the engine's tests.
    readonly property string verdict: !present ? "No qmake here - cannot say whether a build would work"
                                    : complete ? "A cxx-qt build will work here"
                                    : "A cxx-qt build will FAIL here"

    function has(tool) {
        for (var i = 0; i < found.length; ++i)
            if (found[i] === tool)
                return true
        return false
    }

    Column {
        id: col
        anchors.fill: parent
        spacing: 5

        // The verdict, not the version. It is what the panel is for - and
        // what you would quote, so it is selectable.
        SelectableText {
            width: parent.width
            text: root.verdict
            font.pixelSize: 13
            font.bold: true
            color: !root.present ? palette.text
                 : root.complete ? style.okText
                 : style.badText
            wrapMode: TextEdit.Wrap
        }

        // Readings and the four host tools in one block, so a drag takes
        // the lot. Two-of-four present is the classic split-prefix signature
        // and is worth seeing at a glance, which is why each tool keeps its
        // own line and its own info button.
        StatBlock {
            panel: root
            rows: {
                var out = [
                    { label: "version",
                      value: root.value && root.value.version
                             ? root.value.version : "—",
                      statKey: "version" },
                    { label: "from",
                      value: root.value ? root.value.source : "—",
                      statKey: "source" },
                    { label: "target",
                      value: root.value && root.value.target_spec
                             ? root.value.target_spec : "—",
                      statKey: "target_spec" }
                ]
                var tools = ["moc", "rcc", "qmltyperegistrar", "qmlcachegen"]
                for (var i = 0; i < tools.length; i++)
                    out.push({
                        label: tools[i],
                        value: root.present
                               ? (root.has(tools[i]) ? "✓ present" : "✗ missing")
                               : "—",
                        color: !root.present ? palette.text
                               : root.has(tools[i]) ? style.okText
                                                    : style.badText,
                        statKey: root.has(tools[i]) ? "tools_found"
                                                    : "tools_missing"
                    })
                return out
            }
        }
    }
}
