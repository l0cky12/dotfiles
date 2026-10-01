function finiteNumber(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function durationFor(urgency, requested, lowMs, normalMs, maximumMs) {
  if (Number(urgency) === 2) return 0
  var floor = Number(urgency) === 0 ? lowMs : normalMs
  var wanted = Math.max(0, finiteNumber(requested, 0))
  return Math.min(maximumMs, Math.max(floor, wanted))
}

function decodeEntities(text) {
  return text
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, "\"")
    .replace(/&#39;|&apos;/gi, "'")
}

function sanitizeBody(value) {
  var text = String(value || "")
  text = text.replace(/<img\b[^>]*>/gi, "")
  text = text.replace(/<br\s*\/?>/gi, "\n")
  text = text.replace(/<\/p\s*>/gi, "\n")
  text = text.replace(/<[^>]+>/g, "")
  return decodeEntities(text).replace(/\r\n?|\n{3,}/g, "\n").trim().slice(0, 8192)
}

function stringHint(hints, name) {
  try {
    var value = hints ? hints[name] : null
    return value === undefined || value === null ? "" : String(value)
  } catch (e) {
    return ""
  }
}

function knownGlyph(notification) {
  var explicit = stringHint(notification && notification.hints, "desktop-glyph") ||
                 stringHint(notification && notification.hints, "omarchy-glyph")
  if (explicit) return explicit
  var source = (String(notification && notification.appName || "") + " " +
                String(notification && notification.summary || "")).toLowerCase()
  if (/wi-?fi|networkmanager|connected to/.test(source)) return "󰖩"
  if (/bluetooth/.test(source)) return "󰂯"
  if (/battery/.test(source)) return "󰁹"
  if (/volume|audio/.test(source)) return "󰕾"
  return ""
}

function snapshotOf(notification, timestamp, screenName) {
  var n = notification || {}
  var ts = finiteNumber(timestamp, Date.now())
  var id = Math.max(0, Math.round(finiteNumber(n.id, 0)))
  return {
    key: String(Math.round(ts)) + "-" + String(id),
    originalId: id,
    app: String(n.appName || ""),
    desktopEntry: String(n.desktopEntry || ""),
    appIcon: String(n.appIcon || ""),
    summary: String(n.summary || "").slice(0, 2048),
    body: sanitizeBody(n.body),
    image: String(n.image || ""),
    actionsJson: JSON.stringify(Array.prototype.filter.call(n.actions || [], function(action) {
      return action && action.identifier !== "default"
    }).map(function(action) {
      return {identifier: String(action.identifier), text: String(action.text)}
    })),
    glyph: knownGlyph(n),
    urgency: finiteNumber(n.urgency, 1),
    expireTimeout: Math.max(0, finiteNumber(n.expireTimeout, 0)),
    timestamp: ts,
    screenName: String(screenName || ""),
    deadline: 0,
    replay: false,
    restored: false,
    closing: false,
    closeReason: ""
  }
}

var UPDATE_ROLES = ["app", "desktopEntry", "appIcon", "summary", "body", "image", "actionsJson",
                    "glyph", "urgency", "expireTimeout"]

function replacementSnapshot(notification, old) {
  var next = snapshotOf(notification, old.timestamp, old.screenName)
  next.key = old.key
  next.originalId = old.originalId
  return next
}

function updateRoles() { return UPDATE_ROLES }

function shouldBypassDnd(notification, allowedApps) {
  var hints = notification && notification.hints
  var requested = false
  try {
    requested = !!(hints && (hints["desktop-bypass-dnd"] || hints["swaync-bypass-dnd"]))
  } catch (e) {}
  if (!requested || !Array.isArray(allowedApps)) return false
  var app = String(notification && notification.appName || "").toLowerCase()
  for (var i = 0; i < allowedApps.length; i++) {
    if (String(allowedApps[i]).toLowerCase() === app) return true
  }
  return false
}

function localImagePath(value) {
  var text = String(value || "")
  if (text.indexOf("file://") === 0) {
    try { text = decodeURIComponent(text.slice(7)) } catch (e) { return "" }
  }
  return text.charAt(0) === "/" ? text : ""
}

function persistableEntry(value) {
  var out = {}
  for (var key in value) out[key] = value[key]
  out.closing = false
  out.closeReason = ""
  return out
}

function validEntry(value) {
  return value && typeof value === "object" &&
    /^[0-9]{1,20}-[0-9]{1,10}$/.test(String(value.key || "")) &&
    typeof value.summary === "string"
}

if (typeof module !== "undefined") {
  module.exports = {
    durationFor: durationFor,
    sanitizeBody: sanitizeBody,
    knownGlyph: knownGlyph,
    snapshotOf: snapshotOf,
    replacementSnapshot: replacementSnapshot,
    updateRoles: updateRoles,
    shouldBypassDnd: shouldBypassDnd,
    localImagePath: localImagePath,
    persistableEntry: persistableEntry,
    validEntry: validEntry
  }
}
