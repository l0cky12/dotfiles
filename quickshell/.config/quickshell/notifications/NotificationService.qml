pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import "NotificationLogic.js" as Logic

Singleton {
  id: root

  readonly property string stateHome: {
    const configured = Quickshell.env("XDG_STATE_HOME")
    return configured ? configured : Quickshell.env("HOME") + "/.local/state"
  }
  readonly property string stateFilePath: stateHome + "/hyprland-desktop/notifications/state.json"

  property alias popupModel: popupModel
  property bool dnd: NotificationConfig.defaultDnd
  property bool stateLoaded: false
  property int historyCount: 0
  property var liveRefs: ({})
  property var liveKeysById: ({})

  readonly property int visibleCount: popupModel.count

  signal stateChanged()

  ListModel {
    id: popupModel
    dynamicRoles: true
  }

  NotificationPersistence {
    id: persistence
    onOperationFailed: function(operation, detail) {
      console.warn("notifications:", operation, "failed", detail)
    }
  }

  NotificationActions {
    id: actions
    onFocusFailed: function(app) {
      if (NotificationConfig.debug)
        console.warn("notifications: no Hyprland focus match for", app)
    }
  }

  NotificationServer {
    service: root
  }

  function debug() {
    if (!NotificationConfig.debug) return
    const args = Array.prototype.slice.call(arguments)
    args.unshift("notifications:")
    console.log.apply(console, args)
  }

  function focusedScreenName() {
    const monitor = Hyprland.focusedMonitor
    if (monitor && monitor.name) return monitor.name
    return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
  }

  function screenExists(name) {
    for (let i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === name) return true
    return false
  }

  function screenFor(name) {
    return root.screenExists(name) ? name : root.focusedScreenName()
  }

  function durationFor(urgency, requested) {
    return Logic.durationFor(urgency, requested,
      NotificationConfig.lowTimeoutMs,
      NotificationConfig.normalTimeoutMs,
      NotificationConfig.ordinaryMaxTimeoutMs)
  }

  function indexForKey(key) {
    for (let i = 0; i < popupModel.count; i++)
      if (popupModel.get(i).key === key) return i
    return -1
  }

  function countForScreen(name) {
    let count = 0
    for (let i = 0; i < popupModel.count; i++) {
      const row = popupModel.get(i)
      if (root.screenFor(row.screenName) === name) count++
    }
    return count
  }

  function normalizedEntry(value) {
    const v = value || ({})
    return {
      key: String(v.key || ""),
      originalId: Math.max(0, Math.round(Number(v.originalId) || 0)),
      app: String(v.app || ""),
      desktopEntry: String(v.desktopEntry || ""),
      appIcon: String(v.appIcon || ""),
      summary: String(v.summary || ""),
      body: Logic.sanitizeBody(v.body),
      image: String(v.image || ""),
      actionsJson: v.restored || v.replay ? "[]" : String(v.actionsJson || "[]"),
      glyph: String(v.glyph || ""),
      urgency: Number(v.urgency) === 0 || Number(v.urgency) === 2 ? Number(v.urgency) : 1,
      expireTimeout: Math.max(0, Number(v.expireTimeout) || 0),
      timestamp: Number(v.timestamp) || Date.now(),
      screenName: root.screenFor(String(v.screenName || "")),
      deadline: Math.max(0, Number(v.deadline) || 0),
      replay: !!v.replay,
      restored: !!v.restored,
      closing: false,
      closeReason: ""
    }
  }

  function insertEntry(entry, atTop) {
    const normalized = root.normalizedEntry(entry)
    if (atTop) popupModel.insert(0, normalized)
    else popupModel.append(normalized)
    root.stateChanged()
  }

  function receive(notification) {
    notification.tracked = true
    const now = Date.now()
    const entry = Logic.snapshotOf(notification, now, root.focusedScreenName())
    const duration = root.durationFor(entry.urgency, entry.expireTimeout)
    entry.deadline = duration > 0 ? now + duration : 0

    root.liveRefs[entry.key] = notification
    root.liveKeysById[String(entry.originalId)] = entry.key
    notification.closed.connect(function(reason) {
      root.nativeClosed(entry.key, reason)
    })

    const refresh = function() { root.refreshNative(entry.key, notification) }
    const signals = ["summaryChanged", "bodyChanged", "appNameChanged", "appIconChanged",
                     "imageChanged", "urgencyChanged", "expireTimeoutChanged",
                     "desktopEntryChanged", "hintsChanged", "actionsChanged"]
    for (let i = 0; i < signals.length; i++) {
      const signal = notification[signals[i]]
      if (signal && typeof signal.connect === "function") signal.connect(refresh)
    }

    if (root.dnd && !Logic.shouldBypassDnd(notification, NotificationConfig.dndBypassApps)) {
      persistence.writeHistory(entry)
      root.historyCount = Math.min(NotificationConfig.historyLimit, root.historyCount + 1)
      root.debug("stored under DND", entry.app, entry.summary)
      delete root.liveRefs[entry.key]
      delete root.liveKeysById[String(entry.originalId)]
      notification.tracked = false
      root.stateChanged()
      return
    }

    persistence.writeActive(entry)
    root.insertEntry(entry, true)
    root.debug("received", entry.originalId, entry.app, entry.summary)
  }

  function refreshNative(key, notification) {
    if (root.liveRefs[key] !== notification) return
    const index = root.indexForKey(key)
    if (index < 0) return
    const current = popupModel.get(index)
    let updated
    try { updated = Logic.replacementSnapshot(notification, current) }
    catch (e) { return }
    const roles = Logic.updateRoles()
    let changed = false
    for (let i = 0; i < roles.length; i++) {
      const role = roles[i]
      if (current[role] !== updated[role]) {
        popupModel.setProperty(index, role, updated[role])
        changed = true
      }
    }
    if (!changed) return
    const duration = root.durationFor(updated.urgency, updated.expireTimeout)
    popupModel.setProperty(index, "deadline", duration > 0 ? Date.now() + duration : 0)
    const row = popupModel.get(index)
    persistence.writeActive(row)
    root.debug("replaced", row.originalId, row.summary)
  }

  function nativeClosed(key, reason) {
    delete root.liveRefs[key]
    const index = root.indexForKey(key)
    if (index < 0) return
    const row = popupModel.get(index)
    delete root.liveKeysById[String(row.originalId)]
    if (!row.closing) root.requestClose(key, "native")
  }

  function requestClose(key, reason) {
    const index = root.indexForKey(key)
    if (index < 0) return
    if (popupModel.get(index).closing) return
    popupModel.setProperty(index, "closeReason", reason)
    popupModel.setProperty(index, "closing", true)
    if (NotificationConfig.animationMs === 0)
      root.finalizeClose(key)
  }

  function finalizeClose(key) {
    const index = root.indexForKey(key)
    if (index < 0) return
    const entry = popupModel.get(index)
    const reason = String(entry.closeReason || "dismiss")
    const ref = root.liveRefs[key]

    if (!entry.replay) {
      persistence.archive(entry)
      root.historyCount = Math.min(NotificationConfig.historyLimit, root.historyCount + 1)
    }
    popupModel.remove(index)
    delete root.liveRefs[key]
    delete root.liveKeysById[String(entry.originalId)]

    if (ref && reason !== "native") {
      try {
        if (ref.tracked) {
          if (reason === "expire") ref.expire()
          else ref.dismiss()
        }
      } catch (e) {
        root.debug("native close raced", key)
      }
    }
    root.stateChanged()
    root.debug(reason, entry.originalId, entry.summary)
  }

  function dismissKey(key) { root.requestClose(key, "dismiss") }
  function expireKey(key) { root.requestClose(key, "expire") }

  function dismissOne() {
    if (popupModel.count === 0) return "none"
    root.dismissKey(popupModel.get(0).key)
    return "ok"
  }

  function dismissAll() {
    const keys = []
    for (let i = 0; i < popupModel.count; i++) keys.push(popupModel.get(i).key)
    for (let i = 0; i < keys.length; i++) root.dismissKey(keys[i])
    return keys.length ? "ok" : "none"
  }

  function invokeKey(key, identifier = "default") {
    const index = root.indexForKey(key)
    if (index < 0) return "none"
    const entry = popupModel.get(index)
    const ref = root.liveRefs[key]
    let invoked = false
    if (ref && !entry.restored && !entry.replay) {
      try {
        for (let i = 0; i < ref.actions.length; i++) {
          const action = ref.actions[i]
          if (action && action.identifier === identifier) {
            action.invoke()
            invoked = true
            break
          }
        }
      } catch (e) {
        console.warn("notifications: action failed:", e)
      }
    }
    if (!invoked && identifier !== "default") return "none"
    root.requestClose(key, "invoke")
    if (!invoked) actions.focus(entry)
    return invoked ? "invoked" : "focused"
  }

  function invokeLatest() {
    return popupModel.count > 0 ? root.invokeKey(popupModel.get(0).key) : "none"
  }

  function setDnd(value) {
    root.dnd = !!value
    root.saveState()
    root.stateChanged()
    root.debug("DND", root.dnd ? "on" : "off")
    return root.dnd ? "on" : "off"
  }

  function showHistory() {
    // A history view is additive: opening it must not dismiss a live critical
    // card or invalidate a native action. Replace only a previous replay.
    for (let i = popupModel.count - 1; i >= 0; i--)
      if (popupModel.get(i).replay) popupModel.remove(i)
    root.stateChanged()
    persistence.readHistory(function(raw, code) {
      let rows = []
      if (code === 0) {
        try { rows = JSON.parse(raw) }
        catch (e) { console.warn("notifications: corrupt history response:", e) }
      }
      rows = Array.isArray(rows) ? rows.slice(0, NotificationConfig.historyLimit) : []
      root.historyCount = rows.length
      const screen = root.focusedScreenName()
      if (rows.length === 0) {
        const now = Date.now()
        root.insertEntry({
          key: String(now) + "-0", originalId: 0, app: "Notifications",
          desktopEntry: "", appIcon: "", summary: "No recent notifications",
          body: "", image: "", glyph: "󰂚", urgency: 0, expireTimeout: 0,
          timestamp: now, screenName: screen,
          deadline: now + NotificationConfig.lowTimeoutMs,
          replay: true, restored: true
        }, true)
        return
      }
      const now = Date.now()
      for (let i = 0; i < rows.length; i++) {
        const row = rows[i]
        row.screenName = screen
        row.replay = true
        row.restored = true
        const duration = root.durationFor(row.urgency, 0)
        row.deadline = duration > 0 ? now + duration : 0
        root.insertEntry(row, false)
      }
    })
    return "ok"
  }

  function clearHistory() {
    persistence.clearHistory(function() {
      root.historyCount = 0
      root.stateChanged()
    })
    return "ok"
  }

  function restoreActive(raw, code) {
    if (code !== 0) return
    let rows = []
    try { rows = JSON.parse(raw) }
    catch (e) { console.warn("notifications: corrupt active state:", e); return }
    if (!Array.isArray(rows)) return
    const now = Date.now()
    for (let i = rows.length - 1; i >= 0; i--) {
      const row = rows[i]
      if (!Logic.validEntry(row)) continue
      const duration = root.durationFor(row.urgency, row.expireTimeout)
      const deadline = Number(row.deadline) || 0
      if (duration > 0 && deadline > 0 && deadline <= now) {
        persistence.archive(row)
        root.historyCount = Math.min(NotificationConfig.historyLimit, root.historyCount + 1)
        continue
      }
      row.restored = true
      row.replay = false
      row.screenName = root.screenFor(row.screenName)
      if (duration > 0 && deadline <= 0) row.deadline = now + duration
      root.insertEntry(row, true)
    }
    root.debug("restored", rows.length, "active records")
  }

  function loadState(raw) {
    if (root.stateLoaded) return
    try {
      const value = JSON.parse(raw)
      if (value && typeof value.dnd === "boolean") root.dnd = value.dnd
    } catch (e) {}
    root.stateLoaded = true
  }

  function saveState() {
    if (!root.stateLoaded) return
    stateFile.setText(JSON.stringify({version: 1, dnd: root.dnd}, null, 2) + "\n")
  }

  FileView {
    id: stateFile
    path: root.stateFilePath
    atomicWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: {
      root.stateLoaded = true
      root.dnd = NotificationConfig.defaultDnd
      root.saveState()
    }
  }

  IpcHandler {
    target: "notifications"
    function dismissOne(): string { return root.dismissOne() }
    function dismissAll(): string { return root.dismissAll() }
    function toggleDnd(): string { return root.setDnd(!root.dnd) }
    function dndOn(): string { return root.setDnd(true) }
    function dndOff(): string { return root.setDnd(false) }
    function invokeLatest(): string { return root.invokeLatest() }
    function showHistory(): string { return root.showHistory() }
    function clearHistory(): string { return root.clearHistory() }
    function statusJson(): string {
      return JSON.stringify({available: true, dnd: root.dnd,
                             visible: root.visibleCount, history: root.historyCount})
    }
  }

  Component.onCompleted: {
    persistence.initialize(function() {
      persistence.readHistory(function(raw, code) {
        if (code === 0) {
          try {
            const rows = JSON.parse(raw)
            root.historyCount = Array.isArray(rows) ? rows.length : 0
          } catch (e) {}
        }
      })
      persistence.readActive(root.restoreActive)
      persistence.sweep()
    })
  }
}
