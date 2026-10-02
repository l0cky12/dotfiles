pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Clipboard history, backed by the cliphist database that the wl-paste watchers
// in autostart.lua already populate. No second clipboard daemon is started.
//
// cliphist has neither timestamps nor pinning, so both live in a small sidecar
// index keyed by cliphist entry id, kept pruned against the live list. A pin
// belongs to the content, not the id: wiping history re-stores pinned entries,
// and copying one again re-inserts it, both under new ids, so a pin whose id
// vanished moves to a new id with the same preview.
Singleton {
  id: root

  property bool panelVisible: false
  // Screen whose bar icon opened the panel, matching the other panels.
  property string panelScreen: ""

  function togglePanel(screenName) {
    if (panelVisible && panelScreen === screenName) {
      panelVisible = false
      return
    }
    if (screenName === "")
      return
    panelScreen = screenName
    panelVisible = true
    root.refresh()
  }

  // --- entries ---------------------------------------------------------------

  // [{ id, preview, isImage, imgFormat, imgDims, pinned, firstSeen, backfilled }]
  property var entries: []
  property string query: ""
  property int selectedIndex: 0
  property string lastError: ""

  // Pinned first, then cliphist's own recency order.
  readonly property var filtered: {
    const q = root.query.trim().toLowerCase()
    var list = root.entries
    if (q !== "")
      list = list.filter(e => e.preview.toLowerCase().indexOf(q) !== -1)
    return list.filter(e => e.pinned).concat(list.filter(e => !e.pinned))
  }

  readonly property var selected:
    (selectedIndex >= 0 && selectedIndex < filtered.length)
      ? filtered[selectedIndex] : null

  onQueryChanged: root.selectedIndex = 0

  function moveSelection(delta) {
    const n = root.filtered.length
    if (n === 0)
      return
    root.selectedIndex = Math.max(0, Math.min(n - 1, root.selectedIndex + delta))
  }

  // --- sidecar index (timestamps + pins) -------------------------------------

  // id -> { firstSeen: ms, pinned: bool, backfilled: bool, preview?: string }
  // `preview` is kept for pinned entries only, so their pin can follow them.
  // `backfilled` marks entries that already existed the first time we indexed
  // them: their real copy time is unknowable, so the UI shows no relative time
  // for them rather than a misleading "just now".
  property var index: ({})
  property bool indexLoaded: false

  FileView {
    id: indexFile
    path: Quickshell.statePath("clipboard-index.json")
    printErrors: false

    onLoaded: {
      try {
        root.index = JSON.parse(indexFile.text()) || ({})
      } catch (e) {
        root.index = ({})
      }
      root.indexLoaded = true
      root.refresh()
    }
    onLoadFailed: function (error) {
      root.index = ({})
      root.indexLoaded = true
      if (error === FileViewError.FileNotFound)
        root.saveIndex()
      root.refresh()
    }
  }

  function saveIndex() {
    indexFile.setText(JSON.stringify(root.index))
  }

  function togglePin(id) {
    const idx = root.index
    if (!idx[id])
      return
    idx[id].pinned = !idx[id].pinned
    root.index = idx
    root.saveIndex()
    root.rebuild()
  }

  // --- listing ---------------------------------------------------------------

  property var rawLines: []

  function refresh() {
    if (!root.indexLoaded)
      return
    listProc.running = true
  }

  Process {
    id: listProc
    command: ["cliphist", "list"]
    stdout: StdioCollector { id: listOut }
    stderr: StdioCollector { id: listErr }
    onExited: function (code) {
      if (code !== 0) {
        root.lastError = "cliphist unavailable: " + listErr.text.trim()
      } else {
        // Reconcile only after the complete command output is available. An
        // empty successful result is meaningful: it must clear stale rows
        // after the history has been wiped.
        root.rawLines = listOut.text.split("\n").filter(l => l.trim() !== "")
        root.rebuild()
        root.lastError = ""
      }
    }
  }

  // Turns the raw `id<TAB>preview` lines into entries, and reconciles the
  // sidecar index in the same pass (add unseen ids, prune vanished ones).
  function rebuild() {
    const now = Date.now()
    const firstRun = Object.keys(root.index).length === 0
    const idx = root.index
    const seen = ({})
    const list = []
    const rows = []
    var changed = false

    for (var i = 0; i < root.rawLines.length; i++) {
      const line = root.rawLines[i]
      const tab = line.indexOf("\t")
      if (tab <= 0)
        continue
      const id = line.substring(0, tab)
      if (!/^[0-9]+$/.test(id))
        continue
      seen[id] = true
      rows.push({ id: id, preview: line.substring(tab + 1) })
    }

    // Pins whose id is gone, by preview, waiting for their content's new id.
    const orphanedPins = ({})
    for (var old in idx) {
      if (!seen[old] && idx[old].pinned === true && typeof idx[old].preview === "string")
        orphanedPins[idx[old].preview] = idx[old]
    }

    for (var r = 0; r < rows.length; r++) {
      const id = rows[r].id
      const preview = rows[r].preview

      if (!idx[id]) {
        const moved = orphanedPins[preview]
        if (moved) {
          delete orphanedPins[preview]
          idx[id] = {
            firstSeen: moved.firstSeen,
            pinned: true,
            backfilled: moved.backfilled === true,
            preview: preview
          }
          changed = true
        } else {
          idx[id] = {
            firstSeen: now,
            pinned: false,
            // Everything present on the very first index build predates us.
            backfilled: firstRun
          }
        }
      }
      if (idx[id].pinned === true && idx[id].preview !== preview) {
        idx[id].preview = preview
        changed = true
      }

      // "[[ binary data 321 KiB png 1010x609 ]]"
      const m = preview.match(/^\[\[\s*binary data\s+(\S+\s+\S+)\s+(\w+)\s+(\d+x\d+)/)
      list.push({
        id: id,
        preview: preview,
        isImage: m !== null,
        imgFormat: m ? m[2] : "",
        imgDims: m ? m[3] : "",
        imgSize: m ? m[1] : "",
        pinned: idx[id].pinned === true,
        firstSeen: idx[id].firstSeen,
        backfilled: idx[id].backfilled === true
      })
    }

    // Prune index entries cliphist no longer has, so it cannot grow unbounded.
    var pruned = false
    for (var key in idx) {
      if (!seen[key]) {
        delete idx[key]
        pruned = true
      }
    }

    root.index = idx
    root.entries = list
    if (pruned || firstRun || changed)
      root.saveIndex()
    if (root.selectedIndex >= root.filtered.length)
      root.selectedIndex = 0
  }

  // --- actions ---------------------------------------------------------------

  // Ids come from cliphist and are validated numeric before reaching a shell.
  function safeId(id) {
    return /^[0-9]+$/.test(String(id)) ? String(id) : ""
  }

  // Restores the entry as the current clipboard. Images are re-published with
  // their real image MIME type, not as a file path or text.
  function restore(entry) {
    const id = root.safeId(entry ? entry.id : "")
    if (id === "")
      return
    const type = entry.isImage && entry.imgFormat !== ""
      ? " --type image/" + entry.imgFormat : ""
    actionProc.command = ["sh", "-c",
      "cliphist decode " + id + " | wl-copy" + type]
    actionProc.running = true
  }

  function remove(entry) {
    const id = root.safeId(entry ? entry.id : "")
    if (id === "")
      return
    // `cliphist delete` takes the whole list line on stdin.
    actionProc.command = ["sh", "-c",
      "cliphist list | grep -m1 '^" + id + "\t' | cliphist delete"]
    actionProc.running = true
  }

  // Previews of every pinned entry, one per line. screensaver-lock maps them
  // onto current cliphist ids itself, because this list of ids is only as
  // fresh as the last refresh.
  function pinnedPreviews() {
    const out = []
    for (var id in root.index) {
      const item = root.index[id]
      if (item.pinned === true && typeof item.preview === "string")
        out.push(item.preview)
    }
    return out.join("\n")
  }

  // Wipe, preserving pinned entries (they are decoded and re-stored, and the
  // next rebuild moves each pin onto its re-stored id).
  function wipe() {
    const pinned = root.entries.filter(e => e.pinned).map(e => root.safeId(e.id))
                              .filter(s => s !== "")
    actionProc.command = ["sh", "-c",
      "$HOME/.config/hypr/scripts/clipboard-wipe.sh " + pinned.join(" ")]
    actionProc.running = true
  }

  Process {
    id: actionProc
    stdout: StdioCollector {}
    stderr: StdioCollector { id: actionErr }
    onExited: function (code) {
      if (code !== 0)
        root.lastError = actionErr.text.trim() || "clipboard action failed"
      else
        root.lastError = ""
      // Refresh after the mutation has completed, not a fixed interval after
      // it started. The timer then gives cliphist's watcher time to settle.
      pendingRefresh.restart()
    }
  }

  // Gives cliphist a moment to settle before re-listing.
  Timer {
    id: pendingRefresh
    interval: 250
    repeat: false
    onTriggered: root.refresh()
  }

  // --- thumbnails ------------------------------------------------------------

  // id -> file path. Decoded lazily, once per entry, and reused thereafter.
  property var thumbs: ({})
  property var thumbQueue: []
  readonly property string thumbDir: Quickshell.cachePath("clipboard-thumbs")

  Component.onCompleted: mkdirProc.running = true

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.thumbDir]
    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  // Called by a delegate when it actually becomes visible.
  function requestThumb(id) {
    const safe = root.safeId(id)
    if (safe === "" || root.thumbs[safe] !== undefined)
      return
    if (root.thumbQueue.indexOf(safe) !== -1)
      return
    const q = root.thumbQueue.slice()
    q.push(safe)
    root.thumbQueue = q
    root.pumpThumbs()
  }

  // One decode at a time, so scrolling a long list cannot spawn a process storm.
  function pumpThumbs() {
    if (thumbProc.running || root.thumbQueue.length === 0)
      return
    const q = root.thumbQueue.slice()
    const id = q.shift()
    root.thumbQueue = q
    thumbProc.pendingId = id
    thumbProc.command = ["sh", "-c",
      "cliphist decode " + id + " > '" + root.thumbDir + "/" + id + "'"]
    thumbProc.running = true
  }

  Process {
    id: thumbProc
    property string pendingId: ""
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function (code) {
      if (code === 0 && thumbProc.pendingId !== "") {
        // A fresh object, not an in-place mutation: reassigning the same
        // reference emits no change notification, so the delegates' source
        // bindings would never see the new thumbnail.
        const t = ({})
        for (var k in root.thumbs)
          t[k] = root.thumbs[k]
        t[thumbProc.pendingId] = root.thumbDir + "/" + thumbProc.pendingId
        root.thumbs = t
      }
      thumbProc.pendingId = ""
      root.pumpThumbs()
    }
  }

  function thumbFor(id) {
    const safe = root.safeId(id)
    return root.thumbs[safe] !== undefined ? "file://" + root.thumbs[safe] : ""
  }

  // --- formatting ------------------------------------------------------------

  function relativeTime(entry) {
    // Entries that predate the index have no knowable copy time.
    if (!entry || entry.backfilled)
      return ""
    const secs = Math.max(0, (Date.now() - entry.firstSeen) / 1000)
    if (secs < 45) return "just now"
    const mins = Math.floor(secs / 60)
    if (mins < 60) return mins + (mins === 1 ? " minute ago" : " minutes ago")
    const hrs = Math.floor(mins / 60)
    if (hrs < 24) return hrs + (hrs === 1 ? " hour ago" : " hours ago")
    const days = Math.floor(hrs / 24)
    return days + (days === 1 ? " day ago" : " days ago")
  }

  readonly property string glyphClipboard: String.fromCodePoint(0xf0147) // md-clipboard
  readonly property string glyphText: String.fromCodePoint(0xf09a8)      // md-text
  readonly property string glyphImage: String.fromCodePoint(0xf02e9)     // md-image
  readonly property string glyphPin: String.fromCodePoint(0xf0403)       // md-pin
  readonly property string glyphUnpin: String.fromCodePoint(0xf0404)     // md-pin_off
  readonly property string glyphDelete: String.fromCodePoint(0xf0156)    // md-close
  readonly property string glyphSearch: String.fromCodePoint(0xf0349)    // md-magnify
}
