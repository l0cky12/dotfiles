pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
  id: root

  property var values: ({})

  readonly property int warnPercent: intValue("warnPercent", 20)
  readonly property int severePercent: intValue("severePercent", 10)
  readonly property int criticalPercent: intValue("criticalPercent", 5)

  function intValue(name, fallback) {
    const number = Number(root.values[name])
    if (!isFinite(number)) return fallback
    return Math.max(1, Math.min(100, Math.round(number)))
  }

  FileView {
    id: configFile
    path: Qt.resolvedUrl("config.json")
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        root.values = JSON.parse(text()) || ({})
      } catch (error) {
        console.warn("battery: invalid config.json:", error)
        root.values = ({})
      }
    }
    onLoadFailed: root.values = ({})
  }
}
