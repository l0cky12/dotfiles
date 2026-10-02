pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
  id: root

  property var values: ({})

  readonly property string position: {
    const value = stringValue("position", "top-right")
    return ["top-right", "top-left", "bottom-right", "bottom-left"].indexOf(value) >= 0
      ? value : "top-right"
  }
  readonly property int historyLimit: intValue("historyLimit", 10, 0, 100)
  readonly property bool defaultDnd: boolValue("defaultDnd", false)
  readonly property int lowTimeoutMs: intValue("lowTimeoutMs", 5000, 1000, 30000)
  readonly property int normalTimeoutMs: intValue("normalTimeoutMs", 8000, 1000, 30000)
  readonly property int ordinaryMaxTimeoutMs: intValue("ordinaryMaxTimeoutMs", 30000, 1000, 120000)
  readonly property int cardWidth: intValue("cardWidth", 380, 240, 800)
  readonly property int stackGap: intValue("stackGap", 8, 0, 64)
  readonly property int sidePadding: intValue("sidePadding", 12, 0, 64)
  readonly property int singleLinePadding: intValue("singleLinePadding", 7, 0, 64)
  readonly property int multiLinePadding: intValue("multiLinePadding", 10, 0, 64)
  readonly property int iconSize: intValue("iconSize", 40, 12, 128)
  readonly property int iconGap: intValue("iconGap", 12, 0, 64)
  readonly property int vinylSize: intValue("vinylSize", 64, 24, 160)
  readonly property int glyphGap: intValue("glyphGap", 8, 0, 64)
  readonly property int closeSize: intValue("closeSize", 18, 12, 48)
  readonly property int countdownHeight: intValue("countdownHeight", 2, 1, 8)
  readonly property int animationMs: intValue("animationMs", 130, 0, 1000)
  readonly property int closeFadeMs: intValue("closeFadeMs", 100, 0, 1000)
  readonly property bool debug: boolValue("debug", false)
  readonly property var dndBypassApps: Array.isArray(values.dndBypassApps) ? values.dndBypassApps : []
  readonly property var borderWidths: {
    const v = values.borderWidths
    if (!Array.isArray(v) || v.length !== 4)
      return []
    return v.map(function(n) { return Math.max(0, Math.round(Number(n) || 0)) })
  }

  function intValue(name, fallback, minimum, maximum) {
    const n = Number(root.values[name])
    if (!isFinite(n)) return fallback
    return Math.max(minimum, Math.min(maximum, Math.round(n)))
  }

  function boolValue(name, fallback) {
    return typeof root.values[name] === "boolean" ? root.values[name] : fallback
  }

  function stringValue(name, fallback) {
    return typeof root.values[name] === "string" ? root.values[name] : fallback
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
      } catch (e) {
        console.warn("notifications: invalid config.json:", e)
        root.values = ({})
      }
    }
    onLoadFailed: root.values = ({})
  }
}
