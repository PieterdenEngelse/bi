use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(
        // `qml` is a SYMLINK to the repo-root ../qml, shared with the wasm UI.
        //
        // It must be a symlink rather than a "../qml/..." path: cxx-qt copies
        // the given path into the .qrc alias verbatim, so "../qml/Main.qml"
        // under prefix /qt/qml/nixdash normalises to /qt/qml/qml/Main.qml -
        // the module name is eaten, and sibling components then fail to
        // resolve with "No such file or directory". Upstream's own examples
        // symlink for the same reason.
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
