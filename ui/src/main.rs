//! nixdash desktop UI - Qt/QML with a Rust-defined QObject.

pub mod cxxqt_object;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QQuickStyle, QString, QUrl};

fn main() {
    // Fusion, before anything imports Qt Quick Controls - the style cannot be
    // changed once the QML types are registered.
    //
    // Fusion is the one built-in style that takes its colours from the
    // palette, so the dark palette set on the window in Main.qml reaches
    // every button, switch and combo box. Basic hardcodes most of its own
    // colours, which would leave light controls sitting in dark panels.
    QQuickStyle::set_style(&QString::from("Fusion"));

    let mut app = QGuiApplication::new();
    let mut engine = QQmlApplicationEngine::new();

    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/nixdash/qml/Main.qml"));
    }

    if let Some(app) = app.as_mut() {
        app.exec();
    }
}
