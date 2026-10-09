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

    // Header + verdict + 2 rows + gap + 3 target rows + the hint line.
    implicitHeight: 225

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
        anchors.fill: parent
        spacing: 5

        Label {
            width: parent.width
            text: !root.present ? "No Rust on PATH"
                : root.hasEm ? "Can build Qt for WebAssembly"
                : "Cannot build Qt for WebAssembly"
            font.pixelSize: 13
            font.bold: true
            color: !root.present ? palette.text : root.hasEm ? "#2e7d32" : "#ef6c00"
            opacity: root.present ? 1.0 : 0.55
            wrapMode: Text.WordWrap
        }

        StatRow {
            label: "rustc"
            value: root.value && root.value.rustc
                   ? root.value.rustc.split(" ").slice(0, 2).join(" ") : "—"
            panel: root
            statKey: "rustc"
        }
        StatRow {
            label: "toolchain"
            value: root.provenance
            panel: root
            statKey: "rustc_path"
        }

        Item { width: 1; height: 3 }

        StatRow {
            label: "wasm32-unknown"
            value: !root.present ? "—" : root.hasWasm ? "✓ installed" : "✗ absent"
            valueColor: !root.present ? palette.text
                      : root.hasWasm ? "#2e7d32" : "#ef6c00"
            panel: root
            statKey: "has_wasm32_unknown"
        }
        StatRow {
            label: "wasm32-emscripten"
            value: !root.present ? "—" : root.hasEm ? "✓ installed" : "✗ absent"
            valueColor: !root.present ? palette.text
                      : root.hasEm ? "#2e7d32" : "#ef6c00"
            panel: root
            statKey: "has_wasm32_emscripten"
        }
        StatRow {
            label: "lld"
            value: !root.present ? "—" : root.hasLld ? "✓ present" : "✗ absent"
            // Only actually a problem alongside wasm32-unknown-unknown, which
            // is the target that links with it.
            valueColor: !root.present ? palette.text
                      : root.hasLld ? "#2e7d32"
                      : root.hasWasm ? "#c62828" : palette.text
            panel: root
            statKey: "lld_available"
        }

        Label {
            width: parent.width
            visible: root.present && !root.hasEm
            text: "Add a fenix toolchain to the dev shell for the emscripten target."
            font.pixelSize: 10
            opacity: 0.6
            wrapMode: Text.WordWrap
        }
    }
}
