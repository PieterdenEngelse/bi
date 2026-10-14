import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// How this machine is set up, and what to change.
//
// NOT a settings form. This machine is configured declaratively; a form with
// input fields would either write somewhere Nix later overwrites, or fight
// Nix outright. Either way it would lie about where configuration lives.
//
// So each subject answers three questions - what is in effect, where it is
// declared, and what to change it to - and the third is a snippet you copy.
//
// The *rows* stay read-only for that reason. The actions panel at the bottom
// can run shell actions, but never the Nix snippets: those have to go into a
// file you own, and no button can decide which file that is.
Item {
    id: root

    property var panels: []
    property var actions: []
    property string apiBase: ""

    // A run changes exactly the state these sections read, so the shell
    // re-polls afterwards.
    signal ranAction()

    function panel(id) {
        var m = panels.filter(function(p) { return p.id === id })
        return m.length > 0 ? m[0] : null
    }
    function val(id, key) {
        var p = panel(id)
        if (!p || !p.latest || p.latest.value[key] === undefined || p.latest.value[key] === null)
            return "—"
        var v = p.latest.value[key]
        if (Array.isArray(v)) return v.length === 0 ? "none" : v.join(", ")
        if (typeof v === "boolean") return v ? "yes" : "no"
        return String(v)
    }

    ScrollView {
        anchors.fill: parent
        anchors.margins: 14
        contentWidth: availableWidth
        // contentWidth is pinned to the viewport, so a horizontal bar can
        // never be needed - but it is still there, lying across the bottom
        // strip of the page and swallowing clicks that land on it. Text under
        // that strip reads as unselectable for no visible reason.
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
            // Full width, matching every other page. Previously capped at 1100
            // so label/value/provenance read as rows rather than three things
            // scattered across a wide screen; the window now wins.
            width: parent.width
            spacing: 14

            Label {
                text: "Configuration"
                font.bold: true
                font.pixelSize: 18
            }

            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                font.pixelSize: 11
                opacity: 0.7
                text: "These values are read-only by design. Everything here is "
                    + "declared in a Nix file; nixdash shows what is in effect "
                    + "and where it comes from. Changes to Nix config are "
                    + "snippets you paste - only shell actions below can be run. "
                    + "Drag across the lines you want to select them; "
                    + "Ctrl+A takes the whole section."
            }

            // Two and three columns rather than one tall stack: at full width
            // a single column of sections ran well past the window and the
            // page had to be scrolled to see settings that fit beside what is
            // already on screen. Same breakpoints as SubjectPage.
            GridLayout {
                width: parent.width
                columns: root.width >= 1500 ? 3 : (root.width >= 900 ? 2 : 1)
                columnSpacing: 14
                rowSpacing: 14

                ConfigSection {
                    Layout.fillWidth: true
                    title: "NixOS"
                    rows: [
                        { label: "Current generation", value: root.val("generations", "current"),
                          source: "/etc/nixos/configuration.nix → nixos-rebuild switch" },
                        { label: "Reboot pending", value: root.val("generations", "reboot_needed"),
                          source: "/run/booted-system vs /run/current-system" },
                        { label: "Store filesystem", value: root.val("disk", "path"),
                          source: "hardware-configuration.nix" }
                    ]
                }

                // Two Qt sections, because there are two different Qts and
                // conflating them is the mistake this app kept making itself: the
                // one your programs RUN against, and the one you could BUILD
                // with. They are found by completely different mechanisms.
                ConfigSection {
                    Layout.fillWidth: true
                    title: "Qt — what is running"
                    rows: [
                        { label: "Version in use", value: root.val("qt-runtime", "version"),
                          source: "RPATH in the installed binary, not PATH" },
                        { label: "Prefix", value: root.val("qt-runtime", "prefix"),
                          source: "pkgs.qt6.env, via nix/ui.nix" },
                        { label: "Merged environment", value: root.val("qt-runtime", "merged_env"),
                          source: "required for QML and cxx-qt builds" },
                        { label: "Modules linked", value: root.val("qt-runtime", "modules"),
                          source: "" },
                        { label: "Wrapped", value: root.val("qt-runtime", "wrapped"),
                          source: "makeWrapper sets QT_PLUGIN_PATH / QML2_IMPORT_PATH" }
                    ]
                }

                ConfigSection {
                    Layout.fillWidth: true
                    title: "Qt — what could build"
                    rows: [
                        { label: "qmake in use", value: root.val("qt", "qmake"),
                          source: root.val("qt", "source") },
                        { label: "Version", value: root.val("qt", "version"), source: "" },
                        { label: "Prefix", value: root.val("qt", "prefix"), source: "" },
                        { label: "Target spec", value: root.val("qt", "target_spec"), source: "" },
                        { label: "Host tools missing", value: root.val("qt", "tools_missing"),
                          source: "pkgs.qt6.env in your flake's devShell" }
                    ]
                }

                ConfigSection {
                    Layout.fillWidth: true
                    title: "Qt — WebAssembly"
                    rows: [
                        { label: "Browser UI built", value: root.val("qt-wasm", "built"),
                          source: "ui-wasm/build.sh, inside nix develop .#wasm" },
                        { label: "Up to date with qml/", value: root.val("qt-wasm", "stale") === "yes"
                                                                ? "no" : root.val("qt-wasm", "stale"),
                          source: root.val("qt-wasm", "newest_qml_file") },
                        { label: "Qt for wasm", value: root.val("qt-wasm", "sdk_version"),
                          source: root.val("qt-wasm", "sdk") },
                        { label: "Same Qt as desktop", value: root.val("qt-wasm", "versions_match"),
                          source: "" },
                        { label: "Emscripten expected", value: root.val("qt-wasm", "emcc_recommended"),
                          source: "pinned by this Qt; see ~/Projects/qt6-wasm" },
                        { label: "Host Qt for codegen", value: root.val("qt-wasm", "host_env"),
                          source: "QT_HOST_PATH - moc/rcc that run natively" }
                    ]
                }

                ConfigSection {
                    Layout.fillWidth: true
                    title: "Rust"
                    rows: [
                        { label: "rustc", value: root.val("rust", "rustc"),
                          source: root.val("rust", "rustc_path") },
                        { label: "Host target", value: root.val("rust", "host_target"), source: "" },
                        { label: "Installed targets", value: root.val("rust", "targets"),
                          source: "nixpkgs rustc, or a fenix toolchain in the devShell" },
                        { label: "lld available", value: root.val("rust", "lld_available"),
                          source: "pkgs.lld in the devShell" },
                        { label: "Running build", value: root.val("rust-build", "deployed") === "yes"
                                                         ? "deployed (store)" : "dev build",
                          source: root.val("rust-build", "running_exe") },
                        { label: "Current with source", value: root.val("rust-build", "stale") === "yes"
                                                                ? "no" : "yes",
                          source: root.val("rust-build", "newest_source_file") }
                    ]
                }

                // The only editable section on this page. See its own info button
                // for why these four are writable and nothing else is.
                SettingsSection {
                    id: ownSettings
                    Layout.fillWidth: true
                    apiBase: root.apiBase
                    // A write makes a declared value differ from the running one,
                    // which is exactly when the Apply action appears.
                    onChanged: root.ranAction()
                }

                // The other writable sections, in order of how much they can
                // affect: this project's shell, then the whole machine. Same
                // arrangement throughout - a generated file the app owns, never
                // the hand-written one beside it.
                DevShellSection {
                    Layout.fillWidth: true
                    apiBase: root.apiBase
                    onChanged: root.ranAction()
                }

                SystemSection {
                    Layout.fillWidth: true
                    apiBase: root.apiBase
                    onChanged: root.ranAction()
                }
            }


            // Prepared changes, including the Nix snippets that fill the Qt and
            // Rust gaps shown above - in the place you would look for them.
            ActionsPanel {
                id: configActions
                width: parent.width
                // Sizes to its content, like SubjectPage: the page already
                // scrolls, and a nested 280px scroller took the wheel events
                // without ever scrolling, hiding every action below the fifth.
                height: configActions.implicitHeight
                visible: root.actions.length > 0
                actions: root.actions
                errors: []
                apiBase: root.apiBase
                onRanAction: root.ranAction()
            }
        }
    }
}
