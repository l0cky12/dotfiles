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
        description: "help", dispatcher: "exec", arg: "help", mouse: false },
      { modmask: 64, key: "Q", description: "close window",
        dispatcher: "killactive", arg: "", mouse: false }
    ])
    smoke.check("builds palette rows", KeybindsState.rows.length === 5)
    smoke.check("ranks terminal first", KeybindsState.rows[0].description === "terminal")
    smoke.check("keeps same-description actions separate",
                KeybindsState.rows.filter(row => row.description === "calculator").length === 2)
    smoke.check("uses resolved keycode label",
                KeybindsState.rows.some(row => row.shortcut === "SUPER + F1"))
    KeybindsState.query = "calculator-b"
    smoke.check("searches recovered action arguments", KeybindsState.filtered.length === 1)

    // Clicking a row runs it, so a row the palette calls actionable has to
    // carry the command that would be run.
    smoke.check("actionable exec rows carry a command",
                KeybindsState.rows.every(row => !row.actionable
                                             || row.dispatcher !== "exec"
                                             || row.arg !== ""))
    smoke.check("keeps the denylisted dispatcher out of reach",
                KeybindsState.rows.every(row => row.description !== "close window"
                                             || !row.actionable))

    // The search box is one field over both columns: the shortcut and the
    // description each have to match on their own, and case must not matter.
    KeybindsState.query = "super + ret"
    smoke.check("searches the shortcut column",
                KeybindsState.filtered.length === 1
                && KeybindsState.filtered[0].description === "terminal")
    KeybindsState.query = "CALC"
    smoke.check("searches descriptions case-insensitively",
                KeybindsState.filtered.length === 2)
    KeybindsState.query = ""
    smoke.check("an empty query restores every row",
                KeybindsState.filtered.length === KeybindsState.rows.length)
    console.log(smoke.failures === 0
      ? "ok: KeybindsState fixture build and search"
      : "FAIL: " + smoke.failures + " assertion(s) failed")
    Qt.quit()
  }
}
