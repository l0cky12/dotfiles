pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
  id: root

  property bool panelVisible: false
  property string panelScreen: ""
  property bool running: false
  property var result: null
  property string lastError: ""
  property string wallpaperPath: ""

  readonly property string backend: Quickshell.env("NETWORK_CONTROL") ||
    Quickshell.env("HOME") + "/.config/hypr/scripts/network-control"
  readonly property string wallpaperStatePath: {
    const override = Quickshell.env("HYPR_WALLPAPER_STATE_FILE")
    if (override)
      return override
    const stateHome = Quickshell.env("XDG_STATE_HOME") ||
      (Quickshell.env("HOME") + "/.local/state")
    return stateHome + "/hyprland-desktop/wallpaper/current"
  }

  readonly property real pingMs: result ? Math.max(0, Number(result.pingMs) || 0) : 0
  readonly property real downloadMbps: result ? Math.max(0, Number(result.downloadBps) * 8 / 1000000 || 0) : 0
  readonly property real uploadMbps: result ? Math.max(0, Number(result.uploadBps) * 8 / 1000000 || 0) : 0

  function formatMbps(value) {
    if (!(value >= 0))
      return "0.0"
    if (value >= 100)
      return value.toFixed(0)
    if (value >= 10)
      return value.toFixed(1)
    return value.toFixed(2)
  }

  // A logarithmic dial keeps slower links readable without pinning gigabit
  // results against the end stop.
  function gaugeFraction(mbps) {
    return Math.max(0, Math.min(1, Math.log(1 + Math.max(0, mbps)) / Math.log(1001)))
  }

  function togglePanel(screenName) {
    if (root.panelVisible && root.panelScreen === screenName) {
      root.close()
      return
    }
    if (screenName === "")
      return
    root.panelScreen = screenName
    root.panelVisible = true
    root.start()
  }

  function close() {
    root.panelVisible = false
    if (testProc.running)
      testProc.running = false
    root.running = false
  }

  function start() {
    if (root.running)
      return
    root.result = null
    root.lastError = ""
    root.running = true
    testProc.command = [root.backend, "speed-test"]
    testProc.running = true
  }

  Process {
    id: testProc
    stdout: StdioCollector { id: testOut }
    stderr: StdioCollector { id: testErr }
    onExited: function(code) {
      root.running = false
      if (code !== 0) {
        if (root.panelVisible)
          root.lastError = testErr.text.trim() || "Speed test failed. Check your connection."
        return
      }
      try {
        const data = JSON.parse(testOut.text)
        if (!(Number(data.pingMs) >= 0) || !(Number(data.downloadBps) >= 0) ||
            !(Number(data.uploadBps) >= 0))
          throw new Error("missing measurements")
        root.result = data
      } catch (error) {
        root.lastError = "The speed test returned invalid data."
      }
    }
  }

  FileView {
    id: wallpaperState
    path: root.wallpaperStatePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        const data = JSON.parse(wallpaperState.text())
        root.wallpaperPath = typeof data.path === "string" ? data.path : ""
      } catch (error) {
        root.wallpaperPath = ""
      }
    }
    onLoadFailed: root.wallpaperPath = ""
  }
}
