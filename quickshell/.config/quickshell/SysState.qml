pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

// Local system metrics.
//
// Everything comes from /proc and /sys reads except disk usage, which needs df.
// Polling only runs while `active` is set, so an unused SysState costs nothing.
//
// hwmon and DRM card indices are NOT stable across boots, so the sensor paths
// are resolved by matching hwmon/name at startup rather than hardcoded.
Singleton {
  id: root

  // The clock's dashboard drawer used to drive this. With the drawer gone
  // nothing mounts the metric views, so polling stays off until a future
  // consumer sets this.
  property bool active: false

  // --- resolved sensor paths -------------------------------------------------

  property string cpuTempPath: ""   // k10temp temp1_input (Tctl)
  property string gpuTempPath: ""   // amdgpu temp1_input (edge)
  property string gpuBusyPath: ""   // card*/device/gpu_busy_percent

  readonly property bool cpuTempAvailable: cpuTempPath !== ""
  readonly property bool gpuAvailable: gpuBusyPath !== ""

  property string cpuModel: ""
  // The AMD card exposes no product_name under /sys/class/drm/*/device, so the
  // label comes from lspci. This is the RX 6400 -- the RTX 3070 has no readable
  // utilisation (nouveau, no nvidia-smi) and so gets no card at all.
  property string gpuModel: ""

  Component.onCompleted: {
    discoverProc.running = true
    namesProc.running = true
  }

  Process {
    id: namesProc
    command: ["sh", "-c",
      'grep -m1 "model name" /proc/cpuinfo | cut -d: -f2- | sed "s/^ *//"; ' +
      'lspci -nn 2>/dev/null | grep -iE "vga|3d" | grep -i "amd/ati" | ' +
      'sed -E "s/.*\\[AMD\\/ATI\\] //; s/ \\[[0-9a-f]{4}:[0-9a-f]{4}\\].*//" | head -1']
    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "")
          return
        const lines = text.split("\n")
        if (lines.length > 0)
          root.cpuModel = lines[0].trim()
        if (lines.length > 1 && lines[1].trim() !== "")
          root.gpuModel = lines[1].trim()
      }
    }
    stderr: StdioCollector {}
  }

  // --- peripheral battery (UPower) --------------------------------------------
  // This machine has no system battery; the only real one is the mouse. Read
  // natively through UPower rather than shelling out, and hidden entirely when
  // the device is absent -- no invented percentage.
  readonly property var mouseBattery: {
    const list = UPower.devices ? UPower.devices.values : []
    for (var i = 0; i < list.length; i++) {
      const d = list[i]
      if (d && d.isPresent && d.type === UPowerDeviceType.Mouse)
        return d
    }
    return null
  }

  readonly property bool mouseBatteryAvailable: mouseBattery !== null
  // UPower reports percentage as a 0..1 fraction (verified: 0.25 while sysfs
  // capacity read 25), so scale it for display.
  readonly property real mouseBatteryPercent:
    mouseBattery ? mouseBattery.percentage * 100 : 0
  readonly property string mouseBatteryModel: mouseBattery ? mouseBattery.model : ""
  readonly property bool mouseCharging: mouseBattery
    && mouseBattery.state === UPowerDeviceState.Charging

  // False means running on AC, which is always true for this desktop.
  readonly property bool onBattery: UPower.onBattery

  Process {
    id: discoverProc
    command: ["sh", "-c",
      'for h in /sys/class/hwmon/hwmon*; do ' +
      'n=$(cat "$h/name" 2>/dev/null); ' +
      '[ -n "$n" ] && echo "HWMON $n $h"; done; ' +
      'for c in /sys/class/drm/card*/device/gpu_busy_percent; do ' +
      '[ -e "$c" ] && echo "GPUBUSY $c"; done']
    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "")
          return
        const lines = text.trim().split("\n")
        for (var i = 0; i < lines.length; i++) {
          const p = lines[i].trim().split(/\s+/)
          if (p[0] === "HWMON" && p.length >= 3) {
            // temp1_input is Tctl on k10temp and edge on amdgpu.
            if (p[1] === "k10temp")
              root.cpuTempPath = p[2] + "/temp1_input"
            else if (p[1] === "amdgpu")
              root.gpuTempPath = p[2] + "/temp1_input"
          } else if (p[0] === "GPUBUSY" && p.length >= 2) {
            root.gpuBusyPath = p[1]
          }
        }
      }
    }
    stderr: StdioCollector {}
  }

  // --- readings --------------------------------------------------------------

  property real cpuPercent: 0
  property bool cpuSeeded: false
  property real memUsedBytes: 0
  property real memTotalBytes: 0
  property real diskUsedBytes: 0
  property real diskTotalBytes: 0
  property real cpuTempC: 0
  property real gpuTempC: 0
  property real gpuPercent: 0
  property real uptimeSeconds: 0

  readonly property real memFraction: memTotalBytes > 0 ? memUsedBytes / memTotalBytes : 0
  readonly property real diskFraction: diskTotalBytes > 0 ? diskUsedBytes / diskTotalBytes : 0

  // Hardware sensors report millidegrees Celsius; the UI wants Fahrenheit.
  function toF(c) { return c * 9 / 5 + 32 }
  readonly property real cpuTempF: toF(cpuTempC)
  readonly property real gpuTempF: toF(gpuTempC)

  // --- files -----------------------------------------------------------------

  FileView { id: statFile; path: "/proc/stat" }
  FileView { id: memFile; path: "/proc/meminfo" }
  FileView { id: upFile; path: "/proc/uptime" }
  FileView { id: cpuTempFile; path: root.cpuTempPath }
  FileView { id: gpuTempFile; path: root.gpuTempPath }
  FileView { id: gpuBusyFile; path: root.gpuBusyPath }

  property real lastTotal: 0
  property real lastIdle: 0

  function sampleCpu() {
    statFile.reload()
    const first = statFile.text().split("\n")[0]
    if (!first || first.indexOf("cpu ") !== 0)
      return
    const f = first.trim().split(/\s+/).slice(1).map(Number)
    if (f.length < 5)
      return
    var total = 0
    for (var i = 0; i < f.length; i++)
      total += f[i]
    const idle = f[3] + (f.length > 4 ? f[4] : 0)   // idle + iowait

    if (root.lastTotal > 0) {
      const dt = total - root.lastTotal
      const di = idle - root.lastIdle
      if (dt > 0) {
        root.cpuPercent = Math.max(0, Math.min(100, (1 - di / dt) * 100))
        root.cpuSeeded = true
      }
    }
    root.lastTotal = total
    root.lastIdle = idle
  }

  function sampleMem() {
    memFile.reload()
    const t = memFile.text()
    const total = t.match(/MemTotal:\s+(\d+)/)
    const avail = t.match(/MemAvailable:\s+(\d+)/)
    if (total && avail) {
      root.memTotalBytes = parseFloat(total[1]) * 1024
      root.memUsedBytes = root.memTotalBytes - parseFloat(avail[1]) * 1024
    }
  }

  function sampleUptime() {
    upFile.reload()
    const v = parseFloat(upFile.text().trim().split(/\s+/)[0])
    if (!isNaN(v))
      root.uptimeSeconds = v
  }

  function sampleTemps() {
    if (root.cpuTempPath !== "") {
      cpuTempFile.reload()
      const c = parseFloat(cpuTempFile.text())
      if (!isNaN(c))
        root.cpuTempC = c / 1000
    }
    if (root.gpuTempPath !== "") {
      gpuTempFile.reload()
      const g = parseFloat(gpuTempFile.text())
      if (!isNaN(g))
        root.gpuTempC = g / 1000
    }
    if (root.gpuBusyPath !== "") {
      gpuBusyFile.reload()
      const b = parseFloat(gpuBusyFile.text())
      if (!isNaN(b))
        root.gpuPercent = b
    }
  }

  // Fast metrics: only while a consumer has set `active`.
  Timer {
    interval: 1500
    running: root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.sampleCpu()
      root.sampleMem()
      root.sampleUptime()
      root.sampleTemps()
    }
  }

  // Disk is the only external command, so it polls slowly.
  Timer {
    interval: 30000
    running: root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: dfProc.running = true
  }

  Process {
    id: dfProc
    command: ["df", "-B1", "--output=used,size", "/"]
    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "")
          return
        const rows = text.trim().split("\n")
        if (rows.length < 2)
          return
        const p = rows[rows.length - 1].trim().split(/\s+/)
        const used = parseFloat(p[0])
        const size = parseFloat(p[1])
        if (!isNaN(used) && !isNaN(size) && size > 0) {
          root.diskUsedBytes = used
          root.diskTotalBytes = size
        }
      }
    }
    stderr: StdioCollector {}
  }

  // Reset the CPU delta baseline when the panel closes, so the first reading
  // after reopening is not computed against a stale sample.
  onActiveChanged: {
    if (!active) {
      root.lastTotal = 0
      root.cpuSeeded = false
    }
  }

  // --- formatting ------------------------------------------------------------

  function fmtBytes(b) {
    if (!isFinite(b) || b <= 0)
      return "0 B"
    const u = ["B", "KB", "MB", "GB", "TB"]
    var i = 0
    var v = b
    while (v >= 1024 && i < u.length - 1) { v /= 1024; i++ }
    return (v >= 10 ? Math.round(v) : v.toFixed(1)) + " " + u[i]
  }

  function fmtUptime(s) {
    const d = Math.floor(s / 86400)
    const h = Math.floor((s % 86400) / 3600)
    const m = Math.floor((s % 3600) / 60)
    if (d > 0) return d + "d " + h + "h"
    if (h > 0) return h + "h " + m + "m"
    return m + "m"
  }
}
