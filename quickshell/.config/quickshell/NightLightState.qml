pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// State for the night-light schedule panel (Super+Shift+N).
//
// A front-end only: night-light-schedule.py owns the settings file, the sun
// calculation and the switching, and this reads its `status --json`. Every
// Process takes an argument array, so no value is ever parsed as shell.
Singleton {
  id: root

  readonly property string executable: Quickshell.env("NIGHT_LIGHT_SCHEDULE_BIN")
    || Quickshell.env("HOME") + "/.config/hypr/scripts/night-light-schedule.py"
  readonly property string toggleCommand: Quickshell.env("NIGHT_LIGHT_COMMAND")
    || Quickshell.env("HOME") + "/.config/hypr/scripts/night-light.sh"

  property bool panelVisible: false
  property string panelScreen: ""

  // Mirrors of the backend status.
  property string mode: "off"          // off | fixed | sunset
  property string onTime: "21:00"
  property string offTime: "07:00"
  property int sunsetOffset: 0
  property int sunriseOffset: 0
  property var location: null          // { latitude, longitude, place?, source }
  property var today: ({})             // { sunrise, sunset, kind }
  property bool light: false
  property var next: null              // { at, light }
  property string lastError: ""
  property bool detecting: false

  readonly property int offsetStep: 15
  readonly property int maxOffset: 180

  function togglePanel(screenName) {
    if (panelVisible && panelScreen === screenName) {
      panelVisible = false
      return
    }
    if (screenName === "")
      return
    panelScreen = screenName
    panelVisible = true
    refresh()
  }

  function close() { panelVisible = false }
  function refresh() { if (!statusProc.running) statusProc.running = true }

  // --- actions ----------------------------------------------------------------

  // Rapid clicks must not be dropped, so calls made while another is running
  // wait in order; the local mirror is updated first so the next click builds
  // on the value just shown.
  // Process.running only turns true once the child has started, so it cannot
  // guard a second click in the same frame; actionBusy is set synchronously.
  property var pendingCommands: []
  property bool actionBusy: false

  function invoke(command) {
    if (root.actionBusy) {
      root.pendingCommands = root.pendingCommands.concat([command])
      return
    }
    root.actionBusy = true
    actionProc.command = command
    actionProc.running = true
  }

  function setMode(value) {
    root.mode = value
    invoke([root.executable, "set", "mode=" + value])
  }

  function toggleLight() {
    root.light = !root.light
    invoke([root.toggleCommand, "toggle"])
  }

  // Shift a fixed on/off time by `minutes`, wrapping around midnight.
  function shiftClock(which, minutes) {
    const current = which === "on" ? root.onTime : root.offTime
    const parts = current.split(":")
    const total = ((parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10) + minutes)
                   % 1440 + 1440) % 1440
    const value = String(Math.floor(total / 60)).padStart(2, "0") + ":"
                + String(total % 60).padStart(2, "0")
    if (which === "on") root.onTime = value
    else root.offTime = value
    invoke([root.executable, "set", which + "=" + value])
  }

  function shiftOffset(which, minutes) {
    const key = which === "sunset" ? "sunset_offset" : "sunrise_offset"
    const current = which === "sunset" ? root.sunsetOffset : root.sunriseOffset
    const value = Math.max(-root.maxOffset, Math.min(root.maxOffset, current + minutes))
    if (value === current)
      return
    if (which === "sunset") root.sunsetOffset = value
    else root.sunriseOffset = value
    invoke([root.executable, "set", key + "=" + value])
  }

  function saveLocation(latitude, longitude) {
    const lat = parseFloat(latitude)
    const lon = parseFloat(longitude)
    if (!isFinite(lat) || lat < -90 || lat > 90 || !isFinite(lon) || lon < -180 || lon > 180) {
      root.lastError = "Latitude must be -90 to 90 and longitude -180 to 180"
      return
    }
    invoke([root.executable, "set-location", String(lat), String(lon)])
  }

  function detectLocation() {
    if (detectProc.running)
      return
    root.detecting = true
    detectProc.running = true
  }

  // --- formatting -------------------------------------------------------------

  function formatClock(value) {
    // "21:00" -> "9:00 PM"
    const parts = value.split(":")
    const d = new Date(2000, 0, 1, parseInt(parts[0], 10), parseInt(parts[1], 10))
    return Qt.formatDateTime(d, "h:mm AP")
  }

  function formatIso(iso) {
    if (!iso)
      return "--"
    const d = new Date(iso)
    return isNaN(d.getTime()) ? iso : Qt.formatDateTime(d, "h:mm AP")
  }

  function describeOffset(minutes, event) {
    if (minutes === 0)
      return "At " + event
    const size = Math.abs(minutes)
    const amount = size % 60 === 0 ? (size / 60) + " h" : size + " min"
    return amount + (minutes < 0 ? " before " : " after ") + event
  }

  // The switch time an offset produces today, e.g. sunset 18:40 - 30 min.
  function offsetTime(iso, minutes) {
    if (!iso)
      return "--"
    const d = new Date(iso)
    if (isNaN(d.getTime()))
      return "--"
    return Qt.formatDateTime(new Date(d.getTime() + minutes * 60000), "h:mm AP")
  }

  // --- processes --------------------------------------------------------------

  Process {
    id: statusProc
    command: [root.executable, "status", "--json"]
    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "")
          return
        // A queued change would be overwritten by this older snapshot.
        if (root.actionBusy || root.pendingCommands.length > 0)
          return
        try {
          const value = JSON.parse(text)
          root.mode = value.mode
          root.onTime = value.on
          root.offTime = value.off
          root.sunsetOffset = value.sunset_offset
          root.sunriseOffset = value.sunrise_offset
          root.location = value.location
          root.today = value.today || ({})
          root.light = value.light === true
          root.next = value.next
          root.lastError = value.error || ""
        } catch (error) {
          root.lastError = "Invalid schedule status: " + error
        }
      }
    }
    stderr: StdioCollector {}
    onExited: (code, status) => {
      if (code !== 0) root.lastError = "night-light-schedule status is unavailable"
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {}
    stderr: StdioCollector {
      onTextChanged: if (text.trim() !== "") root.lastError = text.trim()
    }
    onExited: (code, status) => {
      root.actionBusy = false
      if (code === 0) root.lastError = ""
      if (root.pendingCommands.length > 0) {
        const command = root.pendingCommands[0]
        root.pendingCommands = root.pendingCommands.slice(1)
        root.invoke(command)
        return
      }
      root.refresh()
    }
  }

  Process {
    id: detectProc
    command: [root.executable, "detect-location"]
    stdout: StdioCollector {}
    stderr: StdioCollector {
      onTextChanged: if (text.trim() !== "") root.lastError = text.trim()
    }
    onExited: (code, status) => {
      root.detecting = false
      if (code === 0) root.lastError = ""
      root.refresh()
    }
  }

  // Keeps "on now" and the next switch current while the panel is open.
  Timer {
    interval: 5000
    running: root.panelVisible
    repeat: true
    onTriggered: root.refresh()
  }
}
