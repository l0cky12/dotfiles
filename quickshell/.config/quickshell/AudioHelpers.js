function nodeProperties(node) {
  return node && node.properties ? node.properties : ({})
}

function propertyText(properties, key) {
  var value = properties[key]
  return value === undefined || value === null ? "" : String(value).trim()
}

function devicePorts(node) {
  var properties = nodeProperties(node)
  var keys = [
    "device.description",
    "node.description",
    "api.alsa.path",
    "card.profile.device"
  ]
  for (var i = 0; i < keys.length; ++i) {
    var value = propertyText(properties, keys[i])
    if (value !== "")
      return [value]
  }
  return []
}

function deviceDescription(node) {
  if (!node)
    return "Unknown"
  return node.description || node.nickname || node.name || "Unknown"
}

function streamLabel(node, desktopEntry) {
  if (desktopEntry && desktopEntry.name)
    return desktopEntry.name
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
  return Math.round(clampVolume(fraction) * 100)
}

if (typeof module !== "undefined") {
  module.exports = {
    devicePorts: devicePorts,
    deviceDescription: deviceDescription,
    streamLabel: streamLabel,
    clampVolume: clampVolume,
    volumePercent: volumePercent
  }
}
