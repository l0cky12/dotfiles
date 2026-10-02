pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// Display backend: per-monitor brightness over DDC/CI, and monitor scale.
//
// Brightness uses ddcutil rather than brightnessctl because this machine has no
// internal panel -- /sys/class/backlight is empty -- so the only brightness
// control available is DDC/CI over i2c to the external monitors. ddcutil runs
// unprivileged here thanks to the logind ACL on the i2c devices; if that ever
// stops being true, `ddcOk` goes false and the panel says so instead of
// presenting a slider that does nothing.
//
// ddcutil's own display indices are NOT stable (they are the inverse of
// Hyprland's monitor ids on this machine and can change across replug), so
// monitors are always addressed by i2c bus, resolved from the DRM connector
// name that `ddcutil detect` reports as `card<N>-<CONNECTOR>`.
Singleton {
  id: root

  property bool panelVisible: false
  // Which screen's panel instance is shown. With Variants-over-screens every
  // bar has its own panel, so without this the popup would open on more than
  // one monitor at once.
  property string panelScreen: ""
  // Monitor targeted by the panel's controls (the selector tabs).
  property string selectedMonitor: ""

  function togglePanel(screenName) {
    if (panelVisible && panelScreen === screenName) {
      panelVisible = false
      return
    }
    if (screenName === "")
      return
    panelScreen = screenName
    selectedMonitor = screenName
    panelVisible = true
  }

  // One entry per monitor:
  //   { name, description, bus, width, height, refresh, x, y, scale,
  //     transform, brightness, maxBrightness, ddcOk }
  // `bus` is -1 until resolved; `ddcOk` is false until a getvcp succeeds.
  property var monitors: []

  property string lastError: ""
  property bool scaleBusy: false

  readonly property var scalePresets: [1.0, 1.25, 1.5, 1.75, 2.0]

  readonly property string glyph: String.fromCodePoint(0xf0379) // md-monitor

  // Only allow shell-safe identifiers through, since monitor names end up in a
  // command string. Hyprland connector names are always of this form.
  readonly property var nameRegex: /^[A-Za-z0-9_-]+$/

  // --- lookup helpers -------------------------------------------------------

  function monitorFor(name) {
    for (var i = 0; i < monitors.length; i++)
      if (monitors[i].name === name)
        return monitors[i]
    return null
  }

  readonly property var selected: monitorFor(selectedMonitor)

  // Replace one monitor entry. The whole array is reassigned so that bindings
  // depending on `monitors` re-evaluate.
  function patchMonitor(name, patch) {
    const next = []
    var found = false
    for (var i = 0; i < monitors.length; i++) {
      const m = monitors[i]
      if (m.name !== name) {
        next.push(m)
        continue
      }
      found = true
      const copy = {}
      for (var k in m)
        copy[k] = m[k]
      for (var p in patch)
        copy[p] = patch[p]
      next.push(copy)
    }
    if (found)
      root.monitors = next
  }

  // Hyprland rejects a scale that does not divide the mode into whole logical
  // pixels (it snaps to the nearest valid value and logs a warning), so presets
  // that cannot apply to a given monitor are offered as disabled.
  function scaleValid(mon, s) {
    if (!mon || !s || s <= 0)
      return false
    const w = mon.width / s
    const h = mon.height / s
    return Math.abs(w - Math.round(w)) < 0.001
        && Math.abs(h - Math.round(h)) < 0.001
  }

  function brightnessFraction(mon) {
    if (!mon || !mon.ddcOk || !mon.maxBrightness)
      return 0
    return Math.max(0, Math.min(1, mon.brightness / mon.maxBrightness))
  }

  // --- monitor discovery ----------------------------------------------------

  // Set when the set of connected monitors changes, so the (comparatively slow)
  // ddcutil detect only runs when the bus map could actually be stale.
  property bool busMapStale: true

  function refreshMonitors() {
    hyprProc.running = true
  }

  Process {
    id: hyprProc
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "")
          return
        var list
        try {
          list = JSON.parse(text)
        } catch (e) {
          root.lastError = "Could not parse hyprctl monitors output"
          return
        }

        const prevNames = root.monitors.map(m => m.name).sort().join(",")
        const next = []
        for (var i = 0; i < list.length; i++) {
          const hm = list[i]
          if (!root.nameRegex.test(hm.name))
            continue
          const old = root.monitorFor(hm.name)
          next.push({
            name: hm.name,
            description: hm.description || hm.model || hm.name,
            bus: old ? old.bus : -1,
            width: hm.width,
            height: hm.height,
            refresh: hm.refreshRate,
            x: hm.x,
            y: hm.y,
            scale: hm.scale,
            transform: hm.transform,
            brightness: old ? old.brightness : 0,
            maxBrightness: old ? old.maxBrightness : 100,
            ddcOk: old ? old.ddcOk : false
          })
        }
        root.monitors = next

        if (next.map(m => m.name).sort().join(",") !== prevNames)
          root.busMapStale = true

        if (root.selectedMonitor === "" || !root.monitorFor(root.selectedMonitor))
          root.selectedMonitor = next.length > 0 ? next[0].name : ""

        if (root.busMapStale) {
          // Cleared on launch rather than on completion: if ddcutil is missing
          // entirely the process never exits, and leaving the flag set would
          // retry it on every poll. Opening the panel re-arms it.
          root.busMapStale = false
          detectProc.running = true
        } else {
          root.refreshBrightness()
        }
      }
    }
    stderr: StdioCollector { id: hyprErr }
    onExited: function (code) {
      if (code !== 0)
        root.lastError = "hyprctl monitors failed: " + hyprErr.text.trim()
    }
  }

  // Map DRM connector -> i2c bus. `detect --terse` output looks like:
  //   Display 1
  //      I2C bus:          /dev/i2c-6
  //      DRM connector:    card2-HDMI-A-3
  Process {
    id: detectProc
    command: ["ddcutil", "detect", "--terse"]
    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "")
          return
        const lines = text.split("\n")
        var bus = -1
        for (var i = 0; i < lines.length; i++) {
          const line = lines[i]
          const busM = line.match(/I2C bus:\s*\/dev\/i2c-(\d+)/)
          if (busM) {
            bus = parseInt(busM[1], 10)
            continue
          }
          const conM = line.match(/DRM.connector:\s*card\d+-(\S+)/)
          if (conM && bus >= 0) {
            root.patchMonitor(conM[1], { bus: bus })
            bus = -1
          }
        }
        root.refreshBrightness()
      }
    }
    stderr: StdioCollector {}
    onExited: function (code) {
      // A non-zero exit still leaves any parsed buses in place; monitors that
      // got none simply stay ddcOk: false.
      if (code !== 0)
        root.refreshBrightness()
    }
  }

  // --- brightness read ------------------------------------------------------

  // One process for all monitors: ddcutil is ~65ms per call, and looping in the
  // shell avoids juggling a Process per monitor.
  function refreshBrightness() {
    if (writeProc.running || flushTimer.running)
      return
    const specs = []
    for (var i = 0; i < monitors.length; i++) {
      const m = monitors[i]
      if (m.bus >= 0 && nameRegex.test(m.name))
        specs.push(m.name + ":" + m.bus)
    }
    if (specs.length === 0)
      return
    // `ddcutil getvcp 10 --brief` prints five fields:
    //   VCP 10 C <current> <max>
    // so the current value is $4 and the maximum is $5.
    readProc.command = ["sh", "-c",
      'for spec in ' + specs.join(" ") + '; do ' +
      'name=${spec%%:*}; bus=${spec##*:}; ' +
      'if out=$(ddcutil --bus "$bus" getvcp 10 --brief 2>/dev/null); then ' +
      'set -- $out; echo "$name ${4:-} ${5:-}"; ' +
      'else echo "$name ERR ERR"; fi; done']
    readProc.running = true
  }

  Process {
    id: readProc
    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "")
          return
        const lines = text.trim().split("\n")
        for (var i = 0; i < lines.length; i++) {
          const parts = lines[i].trim().split(/\s+/)
          if (parts.length < 3)
            continue
          const name = parts[0]
          // Do not clobber a value the user is currently dragging.
          if (root.pendingWrites[name] !== undefined)
            continue
          const cur = parseInt(parts[1], 10)
          const max = parseInt(parts[2], 10)
          if (isNaN(cur) || isNaN(max) || max <= 0) {
            root.patchMonitor(name, { ddcOk: false })
            continue
          }
          root.patchMonitor(name, {
            brightness: cur,
            maxBrightness: max,
            ddcOk: true
          })
        }
      }
    }
    stderr: StdioCollector {}
  }

  // --- brightness write -----------------------------------------------------

  // DDC/CI writes take ~100-200ms, and the slider emits on every mouse move, so
  // writes are coalesced: the local value updates immediately for feedback and
  // the hardware is written once the drag settles.
  property var pendingWrites: ({})

  function setBrightness(name, value) {
    const mon = monitorFor(name)
    if (!mon || !mon.ddcOk || mon.bus < 0)
      return
    const max = mon.maxBrightness || 100
    const v = Math.max(0, Math.min(max, Math.round(value)))
    if (v === mon.brightness && pendingWrites[name] === undefined)
      return
    patchMonitor(name, { brightness: v })
    const p = root.pendingWrites
    p[name] = v
    root.pendingWrites = p
    flushTimer.restart()
  }

  function setBrightnessFraction(name, fraction) {
    const mon = monitorFor(name)
    if (!mon)
      return
    setBrightness(name, fraction * (mon.maxBrightness || 100))
  }

  function stepBrightness(name, delta) {
    const mon = monitorFor(name)
    if (!mon)
      return
    const base = pendingWrites[name] !== undefined
      ? pendingWrites[name] : mon.brightness
    setBrightness(name, base + delta)
  }

  Timer {
    id: flushTimer
    interval: 120
    repeat: false
    onTriggered: root.flushWrites()
  }

  function flushWrites() {
    if (writeProc.running) {
      // Retry once the in-flight write finishes.
      flushTimer.restart()
      return
    }
    const cmds = []
    const names = []
    for (var name in pendingWrites) {
      const mon = monitorFor(name)
      if (!mon || mon.bus < 0)
        continue
      const v = parseInt(pendingWrites[name], 10)
      if (isNaN(v))
        continue
      cmds.push("ddcutil --bus " + mon.bus + " setvcp 10 " + v)
      names.push(name)
    }
    if (cmds.length === 0) {
      root.pendingWrites = ({})
      return
    }
    writeProc.command = ["sh", "-c", cmds.join("; ")]
    writeProc.running = true
  }

  Process {
    id: writeProc
    stdout: StdioCollector {}
    stderr: StdioCollector { id: writeErr }
    onExited: function (code) {
      root.pendingWrites = ({})
      if (code !== 0) {
        const msg = writeErr.text.trim()
        root.lastError = "Brightness write failed" + (msg ? ": " + msg : "")
        // Re-read so the UI falls back to what the hardware actually holds.
        root.refreshBrightness()
      } else {
        root.lastError = ""
      }
    }
  }

  // --- scale ----------------------------------------------------------------

  function setScale(name, scale) {
    const mon = monitorFor(name)
    if (!mon || scaleBusy)
      return
    if (!nameRegex.test(name))
      return
    const s = Number(scale)
    if (!isFinite(s) || s <= 0)
      return
    if (!scaleValid(mon, s)) {
      root.lastError = s + "x does not divide " + mon.width + "x" + mon.height
                     + " evenly on " + name
      return
    }

    const mode = mon.width + "x" + mon.height + "@" + Number(mon.refresh).toFixed(3)
    const pos = mon.x + "x" + mon.y
    // Normalised decimal ("2.0", "1.25") so the written config keeps the same
    // shape as the lines nwg-displays generates.
    var scaleStr = s.toFixed(6).replace(/0+$/, "")
    if (scaleStr.charAt(scaleStr.length - 1) === ".")
      scaleStr += "0"
    const luaMonitor = 'hl.monitor({ output = "' + name
                     + '", mode = "' + mode
                     + '", position = "' + pos
                     + '", scale = ' + scaleStr + ' })'

    root.scaleBusy = true
    root.lastError = ""
    scaleProc.command = ["sh", "-c",
      'set -e; ' +
      "hyprctl eval '" + luaMonitor + "'; " +
      '"$HOME/.config/hypr/scripts/set-monitor-scale.sh" ' + name + ' ' + scaleStr]
    scaleProc.running = true
  }

  Process {
    id: scaleProc
    stdout: StdioCollector { id: scaleOut }
    stderr: StdioCollector { id: scaleErr }
    onExited: function (code) {
      root.scaleBusy = false
      const out = (scaleOut.text + "\n" + scaleErr.text).trim()
      if (code !== 0) {
        root.lastError = "Scale change failed: " + (out || "exit " + code)
      } else if (/invalid|error|failed/i.test(out)) {
        // hyprctl exits 0 even when it refuses or snaps a scale.
        root.lastError = out.split("\n")[0]
      }
      // Read back what actually took effect.
      root.refreshMonitors()
    }
  }

  Component.onCompleted: root.refreshMonitors()

  // --- refresh scheduling ---------------------------------------------------

  Timer {
    // Slow poll: DDC/CI has no change notification, so this is the only way to
    // notice brightness changed by something else (a stray ddcutil call, the
    // monitor's own OSD buttons). Also re-reads scale so external changes show.
    // Poll only while the panel is open; startup discovery prepares bar scrolling, and
    // each tick is an i2c transaction per monitor. triggeredOnStart refreshes
    // as the panel opens; hotplug is still caught by onRawEvent below.
    interval: 10000
    running: root.panelVisible
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshMonitors()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      const n = event.name
      if (n === "monitoradded" || n === "monitorremoved"
          || n === "monitoraddedv2" || n === "configreloaded") {
        root.busMapStale = true
        root.refreshMonitors()
      }
    }
  }
}
