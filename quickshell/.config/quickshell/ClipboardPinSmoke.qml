import Quickshell
import QtQuick

// Headless check that clipboard pins follow their content across new cliphist
// ids (a wipe re-stores pinned entries; copying one again re-inserts it).
// Driven by tests/clipboard-filter.test.sh with a stub `cliphist`.
Scope {
  id: smoke
  property int failures: 0
  function check(name, condition) {
    if (condition) console.log("ok   " + name)
    else { console.log("FAIL " + name); failures += 1 }
  }
  function entry(id) {
    return ClipboardState.entries.find(e => e.id === id) || null
  }

  // Instantiate the singleton now, so its startup index load and empty
  // listing finish before the checks replace its state.
  readonly property var state: ClipboardState

  Timer {
    interval: 800; running: true
    onTriggered: {
      check("index loaded", ClipboardState.indexLoaded)

      ClipboardState.index = {
        "5": { firstSeen: 111, pinned: true, backfilled: false, preview: "keep me" },
        "6": { firstSeen: 222, pinned: false, backfilled: false }
      }
      ClipboardState.rawLines = ["9\tkeep me", "8\tother"]
      ClipboardState.rebuild()
      check("a pin moves to its content's new id",
            entry("9") !== null && entry("9").pinned && entry("9").firstSeen === 111)
      check("other new ids stay unpinned", entry("8") !== null && !entry("8").pinned)
      check("the vanished id is pruned", ClipboardState.index["5"] === undefined)
      check("pinned previews are reported", ClipboardState.pinnedPreviews() === "keep me")

      // Pins made before previews were recorded learn theirs on the next rebuild.
      ClipboardState.index = { "9": { firstSeen: 1, pinned: true, backfilled: false } }
      ClipboardState.rawLines = ["9\tlegacy"]
      ClipboardState.rebuild()
      check("a legacy pin records its preview", ClipboardState.index["9"].preview === "legacy")

      // A pin whose content is gone is not handed to unrelated content.
      ClipboardState.rawLines = ["10\tsomething else"]
      ClipboardState.rebuild()
      check("unrelated content does not inherit a pin", entry("10") !== null && !entry("10").pinned)
      check("no pinned previews remain", ClipboardState.pinnedPreviews() === "")

      console.log(smoke.failures === 0 ? "ok: clipboard pin smoke" : "FAIL: clipboard pin smoke")
      Qt.quit()
    }
  }
}
