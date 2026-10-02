pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Bluetooth adapter and device state, backed by `bluetooth-control status`.
//
// While the panel is closed the list stays warm from BlueZ D-Bus signals plus a
// slow backstop poll, so opening the menu never shows an empty or stale list;
// while it is open the backend is polled every couple of seconds. Results are
// split into the panel's three zones (connected / paired / discovered) and
// diffed into a ListModel per zone, so a poll that changes nothing touches no
// delegates and a poll that changes one battery reading repaints one row
// rather than rebuilding the whole list. A device that connects leaves one
// zone's model and enters another's, which is the move the panel animates.
Singleton {
  id: root

  property bool panelVisible: false
  // Connector name of the screen whose bar opened the panel, matching the
  // other panels: each bar builds its own popup.
  property string panelScreen: ""

  property bool available: false
  property bool powered: false
  property bool scanning: false
  // Sorted device array. Ordering is driven from here; the zone models below
  // are the incrementally-synced views the panel renders.
  property var devices: []
  property string lastError: ""
  property bool actionErrorActive: false
  // Address the last failing action belonged to, or "" for adapter-wide and
  // status-poll failures. The panel routes an error to the row that caused it
  // and keeps the header banner for everything else.
  property string errorAddress: ""

  // Keep the backend below the already-linked Hyprland config tree so adding
  // this widget does not require a separate ~/.local/bin Stow link.
  readonly property string backend: Quickshell.env("HOME")
    + "/.config/hypr/scripts/bluetooth-control"

  readonly property int connectedCount: devices.filter(device => device.connected).length

  // --- glyphs ----------------------------------------------------------------
  //
  // Nerd Font md-* codepoints, matching how the other state singletons carry
  // their glyphs. Device glyphs are keyed off the BlueZ `Icon` property.

  readonly property string glyphOn: String.fromCodePoint(0xf00af)        // md-bluetooth
  readonly property string glyphConnected: String.fromCodePoint(0xf00b1) // md-bluetooth_connect
  readonly property string glyphOff: String.fromCodePoint(0xf00b2)       // md-bluetooth_off
  readonly property string glyphScan: String.fromCodePoint(0xf0448)      // md-radar
  readonly property string glyphTrusted: String.fromCodePoint(0xf0565)   // md-shield_check
  readonly property string glyphUntrusted: String.fromCodePoint(0xf0499) // md-shield_outline
  readonly property string glyphForget: String.fromCodePoint(0xf01b4)    // md-delete
  readonly property string glyphPending: String.fromCodePoint(0xf0772)   // md-loading
  readonly property string glyphError: String.fromCodePoint(0xf0028)     // md-alert_circle

  readonly property var deviceGlyphs: ({
    "audio-headphones": String.fromCodePoint(0xf02cb), // md-headphones
    "audio-headset": String.fromCodePoint(0xf02ce),    // md-headset
    "audio-card": String.fromCodePoint(0xf04c3),       // md-speaker
    "audio-speakers": String.fromCodePoint(0xf04c3),
    "input-keyboard": String.fromCodePoint(0xf030c),   // md-keyboard
    "input-mouse": String.fromCodePoint(0xf037d),      // md-mouse
    "input-gaming": String.fromCodePoint(0xf0295),     // md-gamepad
    "input-tablet": String.fromCodePoint(0xf04f6),     // md-tablet
    "phone": String.fromCodePoint(0xf011c),            // md-cellphone
    "computer": String.fromCodePoint(0xf0322),         // md-laptop
    "video-display": String.fromCodePoint(0xf0379),    // md-monitor
    "printer": String.fromCodePoint(0xf042a),          // md-printer
    "camera-photo": String.fromCodePoint(0xf0100),     // md-camera
    "camera-video": String.fromCodePoint(0xf0100),
    "watch": String.fromCodePoint(0xf0568)             // md-watch
  })

  function glyphForDevice(device) {
    if (!device)
      return root.glyphOn
    return root.deviceGlyphs[device.icon] || root.glyphOn
  }

  readonly property string glyph: {
    if (!available || !powered)
      return root.glyphOff
    if (connectedCount > 0)
      return root.glyphConnected
    return root.glyphOn
  }

  // --- pending actions -------------------------------------------------------
  //
  // Actions are queued rather than gated behind one global `busy` flag, so a
  // 45-second pair does not freeze every other control in the panel. Each
  // queued action marks its device pending immediately, which is what the row
  // renders, so a slow connect is never silent.

  // address (or "" for adapter-wide actions) -> action name
  property var pending: ({})
  property var queue: []
  property string activeAction: ""
  property string activeAddress: ""

  readonly property bool adapterBusy: root.pending[""] !== undefined

  function pendingFor(address) {
    const action = root.pending[address || ""]
    return action === undefined ? "" : action
  }

  function isPending(address) {
    return root.pendingFor(address) !== ""
  }

  function enqueue(action, address, argument) {
    const key = address || ""
    if (root.pendingFor(key) !== "")
      return
    const next = {}
    for (const existing in root.pending)
      next[existing] = root.pending[existing]
    next[key] = action
    root.pending = next
    root.queue = root.queue.concat([{
      action: action,
      address: address || "",
      argument: argument === undefined ? (address || "") : argument
    }])
    root.lastError = ""
    root.actionErrorActive = false
    root.errorAddress = ""
    root.pump()
  }

  function clearPending(key) {
    const next = {}
    for (const existing in root.pending)
      if (existing !== key)
        next[existing] = root.pending[existing]
    root.pending = next
  }

  function pump() {
    if (actionProc.running || root.queue.length === 0)
      return
    const job = root.queue[0]
    root.queue = root.queue.slice(1)
    root.activeAction = job.action
    root.activeAddress = job.address
    const command = [root.backend, job.action]
    if (job.argument !== "")
      command.push(job.argument)
    actionProc.command = command
    actionProc.running = true
  }

  function setPower(enabled) {
    root.enqueue("power", "", enabled ? "on" : "off")
  }

  // Scanning runs outside the action queue: it is long-lived by design and
  // must not block connect/disconnect while it is in progress. Discovered
  // devices appear through the ordinary poll, so results stream in live.
  //
  // The window is deliberately short: expanding the panel's discovery section
  // starts a scan, and a panel left open should not hold the radio in
  // discovery forever. When it lapses the section stays open and its button
  // offers another scan.
  readonly property int scanSeconds: 30
  property bool scanRequested: false

  readonly property bool scanActive: root.scanRequested || root.scanning

  // Owned here rather than in the panel so the expanded/collapsed state (and
  // the scan it drives) survives the popup closing and reopening.
  property bool discoveryExpanded: false

  function setDiscoveryExpanded(expanded) {
    if (root.discoveryExpanded === expanded)
      return
    root.discoveryExpanded = expanded
    // Expanding a discovery section has exactly one meaning, so it scans
    // without a second click; collapsing it puts the radio back down.
    if (expanded)
      root.startScan()
    else
      root.stopScan()
  }

  function startScan() {
    if (scanProc.running)
      return
    root.scanRequested = true
    scanProc.command = [root.backend, "scan", String(root.scanSeconds)]
    scanProc.running = true
  }

  function stopScan() {
    root.scanRequested = false
    if (scanProc.running)
      scanProc.signal(15) // SIGTERM
    scanStopProc.command = [root.backend, "scan", "off"]
    scanStopProc.running = true
  }

  function toggleScan() {
    if (root.scanRequested || root.scanning)
      root.stopScan()
    else
      root.startScan()
  }

  // --- per-device actions ----------------------------------------------------

  function connectDevice(device) {
    if (device && device.address)
      root.enqueue("connect", device.address)
  }

  function disconnectDevice(device) {
    if (device && device.address)
      root.enqueue("disconnect", device.address)
  }

  function pairDevice(device) {
    if (device && device.address)
      root.enqueue("pair", device.address)
  }

  function forgetDevice(device) {
    if (device && device.address)
      root.enqueue("forget", device.address)
  }

  function toggleTrust(device) {
    if (device && device.address)
      root.enqueue(device.trusted ? "untrust" : "trust", device.address)
  }

  // The primary action a row's button and the Enter key both perform.
  function primaryAction(device) {
    if (!device)
      return ""
    if (device.connected)
      return "disconnect"
    return device.paired ? "connect" : "pair"
  }

  function activateDevice(device) {
    if (!device || !device.address)
      return
    if (device.connected)
      root.disconnectDevice(device)
    else if (device.paired)
      root.connectDevice(device)
    else
      root.pairDevice(device)
  }

  // Human label for a queued action, shown while it is pending. Lives here
  // rather than in the panel because the hero card and the device rows both
  // render it.
  function actionLabel(action) {
    switch (action) {
      case "connect": return "Connecting"
      case "disconnect": return "Disconnecting"
      case "pair": return "Pairing"
      case "trust": return "Trusting"
      case "untrust": return "Untrusting"
      case "forget": return "Removing"
      case "power": return "Switching"
      default: return action
    }
  }

  // --- panel -----------------------------------------------------------------

  function togglePanel(screenName) {
    if (panelVisible && panelScreen === screenName) {
      panelVisible = false
      return
    }
    if (screenName === "")
      return
    panelScreen = screenName
    panelVisible = true
    // The list is already warm from background polling; this only trims the
    // worst case of opening right at the end of a poll interval.
    refresh()
  }

  function refresh() {
    if (!statusProc.running)
      statusProc.running = true
  }

  // --- model sync ------------------------------------------------------------

  // One model per panel zone, kept in step with `devices` by address so a poll
  // updates only the roles that actually changed. Splitting here rather than
  // filtering in QML is what makes a connect look like a device moving from
  // the paired zone into the hero: the row leaves one model and enters another.
  ListModel { id: connectedModel }
  ListModel { id: pairedModel }
  ListModel { id: discoveredModel }

  readonly property alias connected: connectedModel
  readonly property alias paired: pairedModel
  readonly property alias discovered: discoveredModel

  readonly property int discoveredCount: discoveredModel.count

  // Connected first, then paired, then merely discovered; alphabetical inside
  // each group so rows do not shuffle between polls.
  function rankOf(device) {
    if (device.connected)
      return 0
    return device.paired ? 1 : 2
  }

  function sortDevices(list) {
    return list.slice().sort(function(a, b) {
      const rank = root.rankOf(a) - root.rankOf(b)
      if (rank !== 0)
        return rank
      const name = a.name.toLowerCase().localeCompare(b.name.toLowerCase())
      if (name !== 0)
        return name
      return a.address.localeCompare(b.address)
    })
  }

  // ListModel roles are typed from the first value they receive, so every
  // field is normalised here; `battery` uses -1 rather than null for "unknown".
  function normalise(entry) {
    return {
      address: String(entry.address || ""),
      name: String(entry.name || entry.address || ""),
      paired: entry.paired === true,
      connected: entry.connected === true,
      trusted: entry.trusted === true,
      icon: String(entry.icon || ""),
      battery: (typeof entry.battery === "number" && isFinite(entry.battery))
        ? Math.round(entry.battery) : -1
    }
  }

  // Splits a sorted poll into the three zones and syncs each. Devices already
  // paired never appear in discovery, so an idle scan cannot duplicate rows.
  function syncModel(list) {
    root.syncInto(connectedModel, list.filter(device => device.connected))
    root.syncInto(pairedModel,
      list.filter(device => device.paired && !device.connected))
    root.syncInto(discoveredModel, list.filter(device => !device.paired))
  }

  function syncInto(deviceModel, list) {
    for (let i = 0; i < list.length; i++) {
      const entry = list[i]
      let found = -1
      for (let j = i; j < deviceModel.count; j++) {
        if (deviceModel.get(j).address === entry.address) {
          found = j
          break
        }
      }
      if (found === -1) {
        deviceModel.insert(i, entry)
        continue
      }
      if (found !== i)
        deviceModel.move(found, i, 1)
      const current = deviceModel.get(i)
      const changes = {}
      let dirty = false
      for (const key in entry) {
        if (current[key] !== entry[key]) {
          changes[key] = entry[key]
          dirty = true
        }
      }
      if (dirty)
        deviceModel.set(i, changes)
    }
    if (deviceModel.count > list.length)
      deviceModel.remove(list.length, deviceModel.count - list.length)
  }

  // Raw stdout of the previous poll. Identical output means nothing moved, so
  // the JSON is not parsed and no binding downstream of `devices` re-evaluates.
  property string lastStatusRaw: ""

  Process {
    id: statusProc
    command: [root.backend, "status"]
    stdout: StdioCollector { id: statusOut }
    stderr: StdioCollector { id: statusErr }

    onExited: function(code) {
      if (code !== 0) {
        root.lastStatusRaw = ""
        root.available = false
        root.powered = false
        root.scanning = false
        root.devices = []
        root.syncModel([])
        root.lastError = statusErr.text.trim() || "Could not read Bluetooth status"
        root.errorAddress = ""
        return
      }
      if (statusOut.text === root.lastStatusRaw)
        return
      root.lastStatusRaw = statusOut.text
      try {
        const state = JSON.parse(statusOut.text)
        root.available = state.available === true
        root.powered = state.powered === true
        root.scanning = state.scanning === true
        const list = root.sortDevices(
          (Array.isArray(state.devices) ? state.devices : []).map(root.normalise))
        root.devices = list
        root.syncModel(list)
        if (!root.actionErrorActive) {
          root.lastError = state.error || ""
          root.errorAddress = ""
        }
      } catch (error) {
        root.lastStatusRaw = ""
        root.available = false
        root.powered = false
        root.scanning = false
        root.devices = []
        root.syncModel([])
        root.lastError = "Bluetooth returned invalid status"
        root.errorAddress = ""
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {}
    stderr: StdioCollector { id: actionErr }

    onExited: function(code) {
      const key = root.activeAddress
      const action = root.activeAction
      root.activeAction = ""
      root.activeAddress = ""
      root.clearPending(key)
      root.actionErrorActive = code !== 0
      if (code !== 0) {
        root.errorAddress = key
        root.lastError = actionErr.text.trim() || ("Bluetooth " + action + " failed")
      }
      // Force a re-parse: the action changed state the poll must pick up.
      root.lastStatusRaw = ""
      root.refresh()
      root.pump()
    }
  }

  Process {
    id: scanProc
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: {
      root.scanRequested = false
      root.lastStatusRaw = ""
      root.refresh()
    }
  }

  Process {
    id: scanStopProc
    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // BlueZ announces power and connection changes on the system bus, so the bar
  // icon follows those signals instead of running the whole status script every
  // eight seconds. Throttled rather than debounced: discovery emits a steady
  // stream of RSSI updates that would otherwise postpone the refresh forever.
  Process {
    id: bluezMonitor
    command: ["gdbus", "monitor", "--system", "--dest", "org.bluez"]
    running: true
    stdout: SplitParser { onRead: if (!bluezSettle.running) bluezSettle.start() }
    stderr: StdioCollector {}
    onExited: bluezMonitorRestart.start()
  }
  Timer { id: bluezMonitorRestart; interval: 30000; onTriggered: bluezMonitor.running = true }
  Timer { id: bluezSettle; interval: 1000; onTriggered: root.refresh() }

  // Polls faster while the panel is open and faster still while discovery is
  // running, so scan hits appear live. The closed-panel poll is only a backstop
  // for signals missed while gdbus was restarting.
  Timer {
    interval: !root.panelVisible ? 60000
            : (root.scanning || root.scanRequested) ? 1200 : 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
