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

        Column {
            // Same measure as MonitorPage: label/value/provenance rows read
            // as rows, not as three things scattered across a wide screen.
            width: Math.min(parent.width, 1100)
            x: (parent.width - width) / 2
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
                    + "snippets you paste - only shell actions below can be run."
            }

            ConfigSection {
                width: parent.width
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

            ConfigSection {
                width: parent.width
                title: "Qt"
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
                width: parent.width
                title: "Rust"
                rows: [
                    { label: "rustc", value: root.val("rust", "rustc"),
                      source: root.val("rust", "rustc_path") },
                    { label: "Host target", value: root.val("rust", "host_target"), source: "" },
                    { label: "Installed targets", value: root.val("rust", "targets"),
                      source: "nixpkgs rustc, or a fenix toolchain in the devShell" },
                    { label: "lld available", value: root.val("rust", "lld_available"),
                      source: "pkgs.lld in the devShell" }
                ]
            }

            ConfigSection {
                width: parent.width
                title: "nixdash itself"
                rows: [
                    { label: "Engine address", value: root.apiBase,
                      source: "services.nixdash.port" },
                    { label: "Desktop UI", value: "installed",
                      source: "services.nixdash.ui.enable" },
                    { label: "Autostart", value: "see your home.nix",
                      source: "services.nixdash.ui.autostart" }
                ]
            }

            // Prepared changes, including the Nix snippets that fill the Qt and
            // Rust gaps shown above - in the place you would look for them.
            ActionsPanel {
                width: parent.width
                height: 280
                visible: root.actions.length > 0
                actions: root.actions
                errors: []
                apiBase: root.apiBase
                onRanAction: root.ranAction()
            }
        }
    }
}
