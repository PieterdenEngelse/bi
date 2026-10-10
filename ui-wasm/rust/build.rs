use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(
        // `qml` is a symlink to the repo-root qml/, shared verbatim with the
        // desktop UI. It must be a symlink *inside this crate* so the paths
        // below contain no "..": cxx-qt copies them into the .qrc alias as-is,
        // and "../qml/X" under prefix /qt/qml/nixdash normalises to
        // /qt/qml/qml/X, eating the module name and breaking every sibling
        // component lookup.
        QmlModule::new("nixdash").qml_files([
            "qml/Main.qml",
            "qml/MemoryPanel.qml",
            "qml/FailedUnitsPanel.qml",
            "qml/ActionsPanel.qml",
            "qml/GenerationsPanel.qml",
            "qml/DiskPanel.qml",
            "qml/MonitorPage.qml",
            "qml/SubjectPage.qml",
            "qml/ConfigPage.qml",
            "qml/ConfigSection.qml",
            "qml/SettingsSection.qml",
            "qml/DevShellSection.qml",
            "qml/SystemSection.qml",
            "qml/GenericPanel.qml",
            "qml/InfoButton.qml",
            "qml/StatRow.qml",
            "qml/QtPanel.qml",
            "qml/RustPanel.qml",
            "qml/Panel.qml",
        ]),
    )
    .qt_module("Qml")
    .qt_module("Quick")
    .files(["src/cxxqt_object.rs"])
    .build();
}
