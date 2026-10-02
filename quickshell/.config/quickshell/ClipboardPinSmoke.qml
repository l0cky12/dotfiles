import Quickshell
import QtQuick

// Headless check that clipboard pins follow their content across new cliphist
// ids when copying one again re-inserts it. Wipes keep the pinned IDs intact.
// Driven by tests/clipboard-filter.test.sh in a private runtime and D-Bus.
Scope {
  id: smoke
  property int failures: 0
  property bool pinFailureObserved: false
  function check(name, condition) {
    if (condition) console.log("ok   " + name)
    else { console.log("FAIL " + name); failures += 1 }
  }
  function entry(id) {
    return ClipboardState.entries.find(e => e.id === id) || null
  }

  // Instantiate the singleton now, so its startup index load and initial
  // listing finish before the checks replace its state.
  readonly property var state: ClipboardState

  Connections {
    target: ClipboardState
    function onLastErrorChanged() {
      if (ClipboardState.lastError.indexOf("could not pin") === 0)
        smoke.pinFailureObserved = true
    }
  }

  Timer {
    interval: 800; running: true
    onTriggered: {
      check("index loaded", ClipboardState.indexLoaded)

      ClipboardState.index = {
        "5": { firstSeen: 111, pinned: true, backfilled: false, preview: "same", hash: "a".repeat(64) },
        "7": { firstSeen: 333, pinned: true, backfilled: false, preview: "same", hash: "b".repeat(64) },
        "6": { firstSeen: 222, pinned: false, backfilled: false }
      }
      ClipboardState.rawRows = [
        { id: "9", preview: "same", hash: "a".repeat(64) },
        { id: "10", preview: "same", hash: "b".repeat(64) },
        { id: "8", preview: "same", hash: "c".repeat(64) },
        { id: "11", preview: "constructor" },
        { id: "12", preview: "toString" },
        { id: "13", preview: "__proto__" }
      ]
      ClipboardState.rebuild()
      check("a pin moves to its content's new id",
            entry("9") !== null && entry("9").pinned && entry("9").firstSeen === 111)
      check("other new ids stay unpinned", entry("8") !== null && !entry("8").pinned)
      check("equal previews can carry two different pins", entry("10").pinned && entry("10").firstSeen === 333)
      check("prototype names stay unpinned", !entry("11").pinned && !entry("12").pinned && !entry("13").pinned)
      check("the vanished id is pruned", ClipboardState.index["5"] === undefined)
      check("IPC reports complete-content hashes", JSON.parse(ClipboardState.pinnedData()).length === 2)

      ClipboardState.togglePin("9")
      check("unpin removes all content metadata", !ClipboardState.index["9"].pinned &&
            ClipboardState.index["9"].preview === undefined && ClipboardState.index["9"].hash === undefined)

      // Legacy pins learn their full-content hash on the next rebuild.
      ClipboardState.index = {
        "9": { firstSeen: 1, pinned: true, backfilled: false },
        "8": { firstSeen: 2, pinned: false, preview: "old plaintext", hash: "c".repeat(64) }
      }
      ClipboardState.rawRows = [
        { id: "9", preview: "legacy", hash: "a".repeat(64) },
        { id: "8", preview: "old plaintext" }
      ]
      ClipboardState.rebuild()
      check("a legacy pin records its hash", ClipboardState.index["9"].hash === "a".repeat(64))
      check("legacy unpinned metadata is scrubbed", ClipboardState.index["8"].preview === undefined &&
            ClipboardState.index["8"].hash === undefined)

      // A pin whose content is gone is not handed to unrelated content.
      ClipboardState.rawRows = [{ id: "10", preview: "something else" }]
      ClipboardState.rebuild()
      check("unrelated content does not inherit a pin", entry("10") !== null && !entry("10").pinned)
      check("no pinned metadata remains", ClipboardState.pinnedData() === "[]")

      // Exercise the real asynchronous hash helper when a user pins a row.
      ClipboardState.rawRows = [
        { id: "10", preview: "fixture content" },
        { id: "98", preview: "decode failure" }
      ]
      ClipboardState.rebuild()
      ClipboardState.togglePin("10")
      check("a pin waits for its hash", !entry("10").pinned)
      pinCheck.start()
    }
  }

  Timer {
    id: pinCheck
    interval: 200
    onTriggered: {
      check("asynchronous pin records a hash", entry("10") !== null && entry("10").pinned &&
            /^[a-f0-9]{64}$/.test(ClipboardState.index["10"].hash))
      ClipboardState.togglePin("10")
      check("asynchronous pin can be unpinned", !entry("10").pinned &&
            ClipboardState.index["10"].preview === undefined && ClipboardState.index["10"].hash === undefined)
      ClipboardState.togglePin("98")
      failureCheck.start()
    }
  }

  Timer {
    id: failureCheck
    interval: 200
    onTriggered: {
      check("failed decode cannot pin a row", entry("98") !== null && !entry("98").pinned &&
            smoke.pinFailureObserved)
      console.log(smoke.failures === 0 ? "ok: clipboard pin smoke" : "FAIL: clipboard pin smoke")
      Qt.quit()
    }
  }
}
