import QtQuick
import QtQuick.Controls

// Rust, judged by what it can actually build.
//
// The version is the least useful thing here: nixpkgs' rustc and a fenix
// toolchain report similar versions but differ in the one way that decides
// whether a wasm build works. So the panel leads with provenance and the
// targets, and names the failure each absence produces.
Panel {
    id: root

    Style { id: style }

    // Header + verdict + 2 rows + gap + 3 target rows + the hint line.
    // Content-driven: a wrapped toolchain path makes the block taller than
    // a fixed height can allow for.
    contentHeight: col.implicitHeight

    readonly property bool present: value && value.rustc
    readonly property string path: value && value.rustc_path ? value.rustc_path : ""

    // Which toolchain this is, from the store path. Worth surfacing because
    // it is otherwise guesswork, and it is the difference between having the
    // emscripten target and not.
    readonly property string provenance:
        path.indexOf("rust-mixed") >= 0 ? "fenix"
      : path.indexOf("rustc-wrapper") >= 0 ? "nixpkgs"
      : path === "" ? "—" : "other"

    readonly property bool hasEm: value ? value.has_wasm32_emscripten : false
    readonly property bool hasWasm: value ? value.has_wasm32_unknown : false
    readonly property bool hasLld: value ? value.lld_available : false

    Column {
        id: col
        anchors.fill: parent
        spacing: 5

        SelectableText {
            width: parent.width
            text: !root.present ? "No Rust on PATH"
                : root.hasEm ? "Can build Qt for WebAssembly"
                : "Cannot build Qt for WebAssembly"
            font.pixelSize: 13
            font.bold: true
            color: !root.present ? palette.text : root.hasEm ? style.okText : style.warnText
            wrapMode: TextEdit.Wrap
        }

        // One block, so a drag takes the whole toolchain picture rather
        // than one line of it. The blank spacer row that used to separate
        // the version from the targets is gone with the per-row items; the
        // labels carry that distinction on their own.
        StatBlock {
            panel: root
            rows: [
                { label: "rustc",
                  value: root.value && root.value.rustc
                         ? root.value.rustc.split(" ").slice(0, 2).join(" ")
                         : "—",
                  statKey: "rustc" },
                { label: "toolchain", value: root.provenance,
                  statKey: "rustc_path" },
                { label: "wasm32-unknown",
                  value: !root.present ? "—"
                         : root.hasWasm ? "✓ installed" : "✗ absent",
                  color: !root.present ? palette.text
                         : root.hasWasm ? style.okText : style.warnText,
                  statKey: "has_wasm32_unknown" },
                { label: "wasm32-emscripten",
                  value: !root.present ? "—"
                         : root.hasEm ? "✓ installed" : "✗ absent",
                  color: !root.present ? palette.text
                         : root.hasEm ? style.okText : style.warnText,
                  statKey: "has_wasm32_emscripten" },
                // lld is only actually a problem alongside
                // wasm32-unknown-unknown, which is the target that links
                // with it.
                { label: "lld",
                  value: !root.present ? "—"
                         : root.hasLld ? "✓ present" : "✗ absent",
                  color: !root.present ? palette.text
                         : root.hasLld ? style.okText
                         : root.hasWasm ? style.badText : palette.text,
                  statKey: "lld_available" }
            ]
        }

        SelectableText {
            width: parent.width
            visible: root.present && !root.hasEm
            text: "Add a fenix toolchain to the dev shell for the emscripten target."
            font.pixelSize: 10
            wrapMode: TextEdit.Wrap
        }
    }
}
