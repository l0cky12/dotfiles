pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
  id: root

  property var values: ({})
  property bool loaded: false

  readonly property int warnPercent: intValue("warnPercent", 20)
  readonly property int severePercent: intValue("severePercent", 10)
  readonly property int criticalPercent: intValue("criticalPercent", 5)

  function intValue(name, fallback) {
    const number = Number(root.values[name])
    if (!isFinite(number)) return fallback
    return Math.max(0, Math.min(100, Math.round(number)))
  }

  function validatedValues(candidate) {
    const defaults = { warnPercent: 20, severePercent: 10, criticalPercent: 5 }
    const source = candidate || ({})
    const names = ["warnPercent", "severePercent", "criticalPercent"]
    const result = ({})
    const enabled = []

    for (let i = 0; i < names.length; i++) {
      const name = names[i]
      const raw = source[name] === undefined ? defaults[name] : source[name]
      if (typeof raw !== "number" || !isFinite(raw) || raw !== Math.round(raw)
          || raw < 0 || raw > 100) {
        console.warn("battery: thresholds must be integer percentages from 0 to 100; using defaults")
        return defaults
      }
      result[name] = raw
      if (result[name] > 0)
        enabled.push(result[name])
    }
    for (let i = 1; i < enabled.length; i++) {
      if (enabled[i - 1] <= enabled[i]) {
        console.warn("battery: enabled thresholds must be strictly descending; using defaults")
        return defaults
      }
    }
    return result
  }

  FileView {
    id: configFile
    path: Qt.resolvedUrl("config.json")
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        root.values = root.validatedValues(JSON.parse(text()))
        root.loaded = true
      } catch (error) {
        console.warn("battery: invalid config.json:", error)
        root.values = ({})
        root.loaded = true
      }
    }
    onLoadFailed: {
      root.values = ({})
      root.loaded = true
    }
  }
}
