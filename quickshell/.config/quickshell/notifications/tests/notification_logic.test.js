const assert = require("node:assert/strict");
const logic = require("../NotificationLogic.js");

assert.equal(logic.durationFor(0, 0, 5000, 8000, 30000), 5000);
assert.equal(logic.durationFor(1, 12000, 5000, 8000, 30000), 12000);
assert.equal(logic.durationFor(1, 90000, 5000, 8000, 30000), 30000);
assert.equal(logic.durationFor(2, 90000, 5000, 8000, 30000), 0);

assert.equal(logic.sanitizeBody("<b>Hello</b><br>world<img src=x>"), "Hello\nworld");
assert.equal(logic.sanitizeBody("A &amp; B"), "A & B");

const notification = {
  id: 7, appName: "NetworkManager", summary: "Wi-Fi connected", body: "Office",
  urgency: 1, expireTimeout: 1000, hints: {}
};
const snapshot = logic.snapshotOf(notification, 1234, "DP-1");
assert.equal(snapshot.key, "1234-7");
assert.equal(snapshot.glyph, "󰖩");
assert.equal(snapshot.screenName, "DP-1");
assert.equal(snapshot.actionsJson, "[]");
const screenshot = logic.snapshotOf({actions: [
  {identifier: "default", text: "Open"},
  {identifier: "edit", text: "Edit"},
  {identifier: "save", text: "Save"}
]}, 1234, "DP-1");
assert.deepEqual(JSON.parse(screenshot.actionsJson), [
  {identifier: "edit", text: "Edit"}, {identifier: "save", text: "Save"}
]);
assert.ok(logic.updateRoles().includes("actionsJson"));

assert.equal(logic.shouldBypassDnd({appName: "Slack", hints: {"swaync-bypass-dnd": true}}, ["Capture"]), false);
assert.equal(logic.shouldBypassDnd({appName: "Capture", hints: {"swaync-bypass-dnd": true}}, ["Capture"]), true);
assert.equal(logic.shouldBypassDnd({appName: "Capture", hints: {}}, ["Capture"]), false);

assert.equal(logic.localImagePath("file:///tmp/a%20b.png"), "/tmp/a b.png");
assert.equal(logic.localImagePath("image://qsimage/1"), "");
assert.equal(logic.validEntry(snapshot), true);
assert.equal(logic.validEntry({key: "../../x", summary: "bad"}), false);

assert.equal(logic.isMediaNotification("Spotify", "/tmp/art.jpg"), true);
assert.equal(logic.isMediaNotification("spotify", "file:///tmp/art.jpg"), true);
assert.equal(logic.isMediaNotification("Spotify", ""), false);
assert.equal(logic.isMediaNotification("Slack", "/tmp/art.jpg"), false);

console.log("notification logic tests: ok");
