pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
  id: root

  readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/arch-updates"
  readonly property int refreshInterval: 90 * 60 * 1000
  readonly property bool checking: countProc.running
  property int repoCount: 0
  property int aurCount: 0
  property int totalCount: 0
  property var repoPackages: []
  property var aurPackages: []
  property bool updating: false
  // True while the displayed counts come from an earlier successful check
  // because the most recent one could not reach the mirrors.
  property bool stale: false

  function refresh() {
    if (!countProc.running && !updateProc.running)
      countProc.running = true
  }

  function update() {
    if (!countProc.running && !updateProc.running) {
      root.updating = true
      updateProc.running = true
    }
  }

  Process {
    id: countProc
    command: [root.script, "count"]
    stdout: StdioCollector { id: countOutput }
    stderr: StdioCollector {}
    onExited: function(code) {
      if (code !== 0) {
        // Keep the last good numbers rather than dropping to zero. A regular
        // poll is safer than immediately repeating a possibly rate-limited
        // AUR request.
        root.stale = true
        pollTimer.restart()
        return
      }
      try {
        const result = JSON.parse(countOutput.text.trim())
        root.repoCount = Math.max(0, Number(result.repo) || 0)
        root.aurCount = Math.max(0, Number(result.aur) || 0)
        root.totalCount = root.repoCount + root.aurCount
        root.repoPackages = Array.isArray(result.repoPackages)
          ? result.repoPackages.map(String)
          : []
        root.aurPackages = Array.isArray(result.aurPackages)
          ? result.aurPackages.map(String)
          : []
        root.stale = false
        // Measure the next poll from this check, so a refresh triggered by an
        // update run does not leave a stale count sitting for a full cycle.
        pollTimer.restart()
      } catch (error) {
        console.warn("UpdatesState: invalid count output:", error)
        root.stale = true
        pollTimer.restart()
      }
    }
  }

  Process {
    id: updateProc
    command: [root.script, "update"]
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function(code) {
      root.updating = false
      if (code === 0) {
        root.repoCount = 0
        root.aurCount = 0
        root.totalCount = 0
        root.repoPackages = []
        root.aurPackages = []
        root.stale = false
      } else {
        root.stale = true
      }
      // yay has already queried AUR during the update. Do not immediately
      // start another request; the regular poll also gives 429 responses time
      // to clear.
      pollTimer.restart()
    }
  }

  Timer {
    id: pollTimer
    interval: root.refreshInterval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
