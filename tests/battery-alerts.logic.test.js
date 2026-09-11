"use strict";

const logic = require(process.argv[2]);
const thresholds = { warn: 20, severe: 10, critical: 5 };

function runSamples(samples, configuredThresholds = thresholds) {
  let state = logic.initialState();
  const alerts = [];
  for (const sample of samples) {
    const result = logic.update(state, sample, configuredThresholds);
    state = result.state;
    alerts.push(...result.alerts);
  }
  return { state, alerts };
}

function sample(percent, powerState, extra = {}) {
  return { hasBattery: true, percent, powerState, ...extra };
}

function levels(result) {
  return result.alerts.map(alert => `${alert.level}:${alert.percent}`);
}

function assert(condition, message) {
  if (!condition)
    throw new Error(message);
}

const edge = runSamples([
  sample(21, "discharging"),
  sample(20, "discharging"),
  sample(19, "indeterminate"), // Transient Unknown must not re-arm warn.
  sample(19, "discharging"),
  sample(12, "discharging"),
  sample(12, "charging"),      // Same-level AC flapping retains suppression.
  sample(12, "discharging"),   // Warn must not replay after the cold start.
  sample(10, "discharging"),
  sample(5, "discharging"),
  { hasBattery: false, percent: 0, powerState: "indeterminate" },
  sample(21, "charging"),      // Above warn establishes a replenished cycle.
  sample(20, "discharging")
]);
assert(levels(edge).join("\n") === "warn:20\nsevere:10\ncritical:5\nwarn:20",
       "threshold edge fixture emitted the wrong alert sequence");

const disabled = logic.update(logic.initialState(), sample(0, "discharging"),
  { warn: 0, severe: 0, critical: 0 });
assert(disabled.alerts.length === 0, "disabled thresholds emitted alerts");

const cold = logic.update(logic.initialState(), sample(4, "discharging"), thresholds);
assert(cold.alerts.length === 1 && cold.alerts[0].level === "critical"
       && cold.state.alerted.warn && cold.state.alerted.severe,
       "cold start did not select only the most severe alert");

const unknownOnBattery = logic.update(logic.initialState(),
  sample(20, "indeterminate", { onBattery: true }), thresholds);
assert(levels(unknownOnBattery)[0] === "warn:20",
       "Unknown + onBattery was not treated as discharging");

const unknownOnAc = logic.update(logic.initialState(),
  sample(5, "indeterminate", { onBattery: false }), thresholds);
assert(unknownOnAc.alerts.length === 0,
       "indeterminate + onBattery false emitted an alert");

const lowCharge = runSamples([
  sample(4, "charging"),
  sample(0, "discharging")
]);
assert(levels(lowCharge).join("\n") === "critical:0",
       "charging below critical suppressed the next discharge alert");

const flapping = runSamples([
  sample(21, "discharging"),
  sample(20, "discharging"),
  sample(12, "discharging"),
  sample(12, "charging"),
  sample(12, "discharging")
]);
assert(levels(flapping).join("\n") === "warn:20",
       "same-level charger flapping replayed warn");

let editedState = runSamples([
  sample(21, "discharging"),
  sample(20, "discharging"),
  sample(10, "discharging")
]).state;
const raisedWarn = { warn: 30, severe: 10, critical: 5 };
editedState = logic.rearmChanged(editedState, thresholds, raisedWarn);
const edited = logic.update(editedState, sample(10, "discharging"), raisedWarn);
assert(edited.alerts.length === 0,
       "config edit replayed warn after severe had already fired");

let rearmedState = logic.update(logic.initialState(), sample(25, "discharging"),
                                thresholds).state;
rearmedState = logic.rearmChanged(rearmedState, thresholds, raisedWarn);
const rearmed = logic.update(rearmedState, sample(25, "discharging"), raisedWarn);
assert(levels(rearmed)[0] === "warn:25", "changed threshold was not re-armed");

process.stdout.write(levels(edge).join("\n") + "\n");
