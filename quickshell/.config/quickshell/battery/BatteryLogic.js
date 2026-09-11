function initialState() {
  return {
    discharging: false,
    lastPercent: null,
    alerted: { warn: false, severe: false, critical: false }
  }
}

function copyState(value) {
  var source = value || initialState()
  var alerted = source.alerted || {}
  return {
    discharging: source.discharging === true,
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
  if (current.powerState !== "discharging")
    return { state: state, alerts: alerts }

  var thresholds = configuredThresholds || {}
  var levels = [
    { level: "warn", threshold: boundedPercent(thresholds.warn, 20) },
    { level: "severe", threshold: boundedPercent(thresholds.severe, 10) },
    { level: "critical", threshold: boundedPercent(thresholds.critical, 5) }
  ]
  for (var i = 0; i < levels.length; i++) {
    var item = levels[i]
    var crossed = item.threshold > 0 && percent <= item.threshold &&
      (state.lastPercent === null || state.lastPercent > item.threshold)
    if (!state.alerted[item.level] && crossed) {
      alerts.push({ level: item.level, threshold: item.threshold, percent: percent })
      state.alerted[item.level] = true
    }
  }

  state.discharging = true
  state.lastPercent = percent
  return { state: state, alerts: alerts }
}

if (typeof module !== "undefined") {
  module.exports = {
    initialState: initialState,
    update: update
  }
}
