pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// UI projection of desktop-mode. QML never infers backend state: every icon
// and row is built from the controller's observed JSON status.
Singleton {
  id: root

  readonly property string executable: Quickshell.env("HOME") + "/.local/bin/desktop-mode"
  property bool panelVisible: false
  property string panelScreen: ""
  property var modes: []
  property string lastError: ""
  property bool daemonRunning: false
  property int warmTemperature: 1000
  property int normalTemperature: 6500
  property var durationPresets: ["15m", "30m", "1h"]

  readonly property var metadata: ({
    "night-light": { label: "Night light", glyph: String.fromCodePoint(0xf0594), detail: root.warmTemperature + "K warm display" },
    // badge is optional short text drawn beside the glyph in the bar pill.
    // DND carries one because the bell glyph alone is easy to miss.
    "do-not-disturb": { label: "Do not disturb", glyph: String.fromCodePoint(0xf0a91), badge: "DND", detail: "Hide toasts, preserve history" },
    "stay-awake": { label: "Stay awake", glyph: String.fromCodePoint(0xf0f2e), detail: "Skip idle screensaver and lock" },
    "screensaver-auto": { label: "Automatic screensaver", glyph: String.fromCodePoint(0xf06a9), detail: "Run after configured inactivity" }
  })

  function mode(name) {
    for (let i = 0; i < modes.length; i++)
      if (modes[i].name === name) return modes[i]
    return { name: name, desired: false, observed: false, available: false,
             expires_at: null, error: "Status unavailable" }
  }

  function togglePanel(screenName) {
    if (screenName === "") return
    if (panelVisible && panelScreen === screenName) {
      panelVisible = false
      return
    }
    panelScreen = screenName
    panelVisible = true
    refresh()
  }

  function close() { panelVisible = false }
  function refresh() { if (!statusProc.running) statusProc.running = true }

  function invoke(args) {
    if (actionProc.running) return
    actionProc.command = [root.executable].concat(args)
    actionProc.running = true
  }

  function toggle(name) { invoke(["toggle", name]) }
  function timed(name, duration) { invoke(["enable", name, "--for", duration]) }
  function screensaver() { invoke(["action", "screensaver"]) }

  Process {
    id: statusProc
    command: [root.executable, "status", "--json"]
    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "") return
        try {
          const value = JSON.parse(text)
          root.modes = value.modes || []
          root.daemonRunning = value.daemon === true
          const settings = value.settings || ({})
          root.warmTemperature = settings.warm_temperature || 1000
          root.normalTemperature = settings.normal_temperature || 6500
          root.durationPresets = settings.duration_presets || ["15m", "30m", "1h"]
          root.lastError = ""
        } catch (error) {
          root.lastError = "Invalid desktop-mode status: " + error
        }
      }
    }
    stderr: StdioCollector {}
    onExited: (code, status) => {
      if (code !== 0) root.lastError = "desktop-mode status is unavailable"
    }
  }

  Process {
    id: actionProc
    command: [root.executable, "status"]
    stdout: StdioCollector {}
    stderr: StdioCollector {
      onTextChanged: if (text.trim() !== "") root.lastError = text.trim()
    }
    onExited: (code, status) => {
      if (code === 0) root.lastError = ""
      refreshDelay.restart()
    }
  }

  Timer {
    id: refreshDelay
    interval: 150
    onTriggered: root.refresh()
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
