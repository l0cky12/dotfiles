function nodeProperties(node) {
  return node && node.properties ? node.properties : ({})
}

function propertyText(properties, key) {
  var value = properties[key]
  return value === undefined || value === null ? "" : String(value).trim()
}

function isOutputDevice(node) {
  return !!(node && node.audio && node.isSink && !node.isStream)
}

function isInputDevice(node) {
  return !!(node && node.audio && !node.isSink && !node.isStream)
}

function isPlaybackStream(node) {
  return !!(node && node.audio && node.isStream && !node.isSink)
}

function deviceDetail(node) {
  var properties = nodeProperties(node)
  var keys = [
    "device.description",
    "node.description",
    "api.alsa.path"
  ]
  for (var i = 0; i < keys.length; ++i) {
    var value = propertyText(properties, keys[i])
    if (value !== "")
      return value
  }
  return ""
}

function deviceDescription(node) {
  if (!node)
    return "Unknown"
  return node.description || node.nickname || node.name || "Unknown"
}

function desktopEntryFor(node, desktopEntries) {
  var desktopId = propertyText(nodeProperties(node), "application.desktop-entry")
  if (desktopId === "" || !desktopEntries)
    return null
  return desktopEntries.byId(desktopId)
    || desktopEntries.byId(desktopId.replace(/\.desktop$/, ""))
    || null
}

function streamLabel(node) {
  var properties = nodeProperties(node)
  return String(properties["application.name"]
    || properties["application.process.binary"]
    || (node && (node.description || node.nickname || node.name))
    || "Application")
}

function clampVolume(fraction) {
  var value = Number(fraction)
  if (!isFinite(value))
    value = 0
  return Math.max(0, Math.min(1, value))
}

function volumePercent(fraction) {
  var value = Number(fraction)
  return Math.round((isFinite(value) ? value : 0) * 100)
}

if (typeof module !== "undefined") {
  module.exports = {
    isOutputDevice: isOutputDevice,
    isInputDevice: isInputDevice,
    isPlaybackStream: isPlaybackStream,
    deviceDetail: deviceDetail,
    deviceDescription: deviceDescription,
    desktopEntryFor: desktopEntryFor,
    streamLabel: streamLabel,
    clampVolume: clampVolume,
    volumePercent: volumePercent
  }
}
