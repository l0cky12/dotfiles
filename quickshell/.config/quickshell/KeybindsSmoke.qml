import Quickshell
import QtQuick

// Headless search/build fixture for the state used by KeybindsPanel.qml.
Scope {
  id: smoke
  property int failures: 0

  // Compile the real panel without constructing its layer-shell window; this
  // keeps the fixture headless while catching panel/type syntax regressions.
  Component {
    id: panelFactory
    KeybindsPanel { ownerScreen: "smoke" }
  }

  function check(name, condition) {
    if (condition)
      console.log("ok   " + name)
    else {
      console.log("FAIL " + name)
      failures += 1
    }
  }

  Component.onCompleted: {
    smoke.check("loads KeybindsPanel component", panelFactory.status === Component.Ready)
    KeybindsState.build([
      { modmask: 64, key: "Return", description: "terminal",
        dispatcher: "exec", arg: "kitty", mouse: false },
      { modmask: 65, key: "C", description: "calculator",
        dispatcher: "exec", arg: "calculator-a", mouse: false },
      { modmask: 68, key: "Q", description: "calculator",
        dispatcher: "exec", arg: "calculator-b", mouse: false },
      { modmask: 64, key: "", keycode: 67, key_label: "F1",
        description: "help", dispatcher: "exec", arg: "help", mouse: false }
    ])
    smoke.check("builds palette rows", KeybindsState.rows.length === 4)
    smoke.check("ranks terminal first", KeybindsState.rows[0].description === "terminal")
    smoke.check("keeps same-description actions separate",
                KeybindsState.rows.filter(row => row.description === "calculator").length === 2)
    smoke.check("uses resolved keycode label",
                KeybindsState.rows.some(row => row.shortcut === "SUPER + F1"))
    KeybindsState.query = "calculator-b"
    smoke.check("searches recovered action arguments", KeybindsState.filtered.length === 1)
    console.log(smoke.failures === 0
      ? "ok: KeybindsState fixture build and search"
      : "FAIL: " + smoke.failures + " assertion(s) failed")
    Qt.quit()
  }
}
