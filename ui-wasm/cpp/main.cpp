#include <QtGui/QGuiApplication>
#include <QtQml/QQmlApplicationEngine>
#include <QtQuickControls2/QQuickStyle>

int main(int argc, char* argv[])
{
  // Must happen before any QML imports Qt Quick Controls - the style cannot
  // be changed once those types are registered. Fusion is the built-in style
  // that reads its colours from the palette, so the dark palette set in
  // Main.qml reaches every control. Kept identical to the desktop entry
  // point in ui/src/main.rs; the two UIs must not diverge in appearance.
  QQuickStyle::setStyle(QStringLiteral("Fusion"));

  QGuiApplication app(argc, argv);
  QQmlApplicationEngine engine;
  const QUrl url(QStringLiteral("qrc:/qt/qml/nixdash/qml/Main.qml"));
  engine.load(url);
  if (engine.rootObjects().isEmpty())
    return -1;
  return app.exec();
}
