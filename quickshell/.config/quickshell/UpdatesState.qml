pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
  id: root

  readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/arch-updates"
  readonly property int refreshInterval: 15 * 60 * 1000
  readonly property int retryInterval: 2 * 60 * 1000
  property int repoCount: 0
  property int aurCount: 0
  property int totalCount: 0
  property bool updating: false
  // True while the displayed counts come from an earlier successful check
  // because the most recent one could not reach the mirrors.
  property bool stale: false

  function refresh() {
    if (!countProc.running && !updateProc.running)
      countProc.running = true
  }

  function update() {
    if (!updateProc.running) {
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
        // Keep the last good numbers rather than dropping to zero, and come
        // back sooner than the regular cadence.
        root.stale = true
        retryTimer.restart()
        return
      }
      try {
        const result = JSON.parse(countOutput.text.trim())
        root.repoCount = Math.max(0, Number(result.repo) || 0)
        root.aurCount = Math.max(0, Number(result.aur) || 0)
        root.totalCount = root.repoCount + root.aurCount
        root.stale = false
        retryTimer.stop()
        // Measure the next poll from this check, so a refresh triggered by an
        // update run does not leave a stale count sitting for a full cycle.
        pollTimer.restart()
      } catch (error) {
        console.warn("UpdatesState: invalid count output:", error)
        root.stale = true
        retryTimer.restart()
      }
    }
  }

  Process {
    id: updateProc
    command: [root.script, "update"]
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function() {
      root.updating = false
      root.refresh()
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

  Timer {
    id: retryTimer
    interval: root.retryInterval
    repeat: false
    onTriggered: root.refresh()
  }
}
