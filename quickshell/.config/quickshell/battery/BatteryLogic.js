function initialState() {
  return {
    lastPercent: null,
    alerted: { warn: false, severe: false, critical: false }
  }
}

function copyState(value) {
  var source = value || initialState()
  var alerted = source.alerted || {}
  return {
    lastPercent: source.lastPercent !== null && source.lastPercent !== undefined
                 && isFinite(Number(source.lastPercent))
      ? Number(source.lastPercent) : null,
    alerted: {
      warn: alerted.warn === true,
      severe: alerted.severe === true,
      critical: alerted.critical === true
    }
  }
}

function normalizedThresholds(configuredThresholds) {
  var thresholds = configuredThresholds || {}
  return {
    warn: boundedPercent(thresholds.warn, 20),
    severe: boundedPercent(thresholds.severe, 10),
    critical: boundedPercent(thresholds.critical, 5)
  }
}

function rearmChanged(previousState, previousThresholds, configuredThresholds) {
  var state = copyState(previousState)
  var before = normalizedThresholds(previousThresholds)
  var after = normalizedThresholds(configuredThresholds)
  var levels = ["warn", "severe", "critical"]
  var changed = false

  for (var i = 0; i < levels.length; i++) {
    var level = levels[i]
    if (before[level] !== after[level]) {
      state.alerted[level] = false
      changed = true
    }
  }
  if (changed)
    state.lastPercent = null
  return state
}

function boundedPercent(value, fallback) {
  var number = Number(value)
  if (!isFinite(number)) return fallback
  return Math.max(0, Math.min(100, Math.round(number)))
}

function update(previousState, sample, configuredThresholds) {
  var state = copyState(previousState)
  var current = sample || {}
  var alerts = []

  // A missing battery is deliberately inert. In particular, transient UPower
  // discovery failures must not create a new discharge cycle.
  if (current.hasBattery !== true)
    return { state: state, alerts: alerts }

  var percent = boundedPercent(current.percent, 0)
  if (current.powerState === "charging") {
    state = initialState()
    state.lastPercent = percent
    return { state: state, alerts: alerts }
  }
  if (current.powerState !== "discharging"
      && !(current.powerState === "indeterminate" && current.onBattery === true))
    return { state: state, alerts: alerts }

  var thresholds = normalizedThresholds(configuredThresholds)
  var levels = [
    { level: "warn", threshold: thresholds.warn },
    { level: "severe", threshold: thresholds.severe },
    { level: "critical", threshold: thresholds.critical }
  ]
  if (state.lastPercent === null) {
    var mostSevere = -1
    for (var coldIndex = 0; coldIndex < levels.length; coldIndex++) {
      var coldItem = levels[coldIndex]
      if (!state.alerted[coldItem.level] && coldItem.threshold > 0
          && percent <= coldItem.threshold)
        mostSevere = coldIndex
    }
    if (mostSevere >= 0) {
      for (var lessSevere = 0; lessSevere < mostSevere; lessSevere++) {
        if (levels[lessSevere].threshold > 0
            && percent <= levels[lessSevere].threshold)
          state.alerted[levels[lessSevere].level] = true
      }
      var selected = levels[mostSevere]
      alerts.push({ level: selected.level, threshold: selected.threshold,
                    percent: percent })
      state.alerted[selected.level] = true
    }
    state.lastPercent = percent
    return { state: state, alerts: alerts }
  }

  for (var i = 0; i < levels.length; i++) {
    var item = levels[i]
    var crossed = item.threshold > 0 && percent <= item.threshold &&
      (state.lastPercent === null || state.lastPercent > item.threshold)
    if (!state.alerted[item.level] && crossed) {
      alerts.push({ level: item.level, threshold: item.threshold, percent: percent })
      state.alerted[item.level] = true
    }
  }

  state.lastPercent = percent
  return { state: state, alerts: alerts }
}

if (typeof module !== "undefined") {
  module.exports = {
    initialState: initialState,
    rearmChanged: rearmChanged,
    update: update
  }
}
