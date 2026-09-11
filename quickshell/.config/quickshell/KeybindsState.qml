pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Keybindings palette. The collector keeps live `hyprctl binds` authoritative,
// then replays keybindings.lua only to recover action metadata hidden by
// Hyprland's __lua dispatcher.
//
// Rows are kept as structured records; the pretty "SUPER SHIFT + F" string is
// display only and is never reparsed to work out what to run.
Singleton {
  id: root

  property bool panelVisible: false
  // Screen the palette opened on, matching the other panels.
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

  function close() {
    root.panelVisible = false
  }

  // --- ordering ---------------------------------------------------------------
  // Matched in order against the row's description; the FIRST rule that matches
  // wins, so specific patterns must come before broad ones -- "files here
  // (terminal cwd)" has to be caught by the file-manager rule before the
  // terminal rule sees it. Ties inside a rank sort alphabetically, so anchored
  // patterns separate the headline entry from its variants. Edit this table to
  // re-prioritise the list; rules that match nothing cost nothing.
  readonly property var priorityRules: [
    { rank: 0, re: /^keybindings$/i },
    { rank: 1, re: /^application launcher$/i },
    { rank: 2, re: /^terminal$/i },
    { rank: 3, re: /^browser$/i },
    { rank: 4, re: /^files$/i },
    { rank: 5, re: /^lmenu root$/i },
    { rank: 6, re: /^power menu$/i },
    { rank: 7, re: /^theme picker$/i },
    { rank: 8, re: /fullscreen/i },
    { rank: 9, re: /maximize/i },
    { rank: 10, re: /^close window$/i },
    { rank: 11, re: /close all windows/i },
    { rank: 12, re: /lock screen/i },
    { rank: 13, re: /floating \/ tiling/i },
    { rank: 14, re: /^split /i },
    { rank: 15, re: /coding agent/i },
    { rank: 16, re: /^universal (copy|cut|paste)$/i },
    { rank: 17, re: /clipboard history/i },
    { rank: 18, re: /audio panel|volume|mute|^play \/ pause$|^pause$|^(next|previous) track$|stop playback|spotify|\bmedia\b/i },
    { rank: 19, re: /bluetooth/i },
    { rank: 20, re: /wi-?fi|network/i },
    { rank: 21, re: /emoji/i },
    { rank: 22, re: /colour picker/i },
    { rank: 23, re: /screenshot/i },
    { rank: 24, re: /screen recording/i },
    { rank: 25, re: /calculator/i },
    { rank: 26, re: /drop-down terminal/i },
    { rank: 27, re: /web app manager/i },
    { rank: 28, re: /files here/i },
    { rank: 29, re: /^(next|previous|former) workspace$/i },
    { rank: 30, re: /^workspace [0-9]+$/i },
    { rank: 31, re: /^move to workspace/i },
    { rank: 32, re: /^move silently to workspace/i },
    { rank: 33, re: /swap window/i },
    { rank: 34, re: /^focus /i },
    { rank: 35, re: /move window/i },
    { rank: 36, re: /resize|expand window|shrink window/i },
    { rank: 37, re: /notification/i },
    { rank: 38, re: /window transparency/i },
    { rank: 39, re: /window gaps/i },
    { rank: 40, re: /night light/i },
    { rank: 41, re: /stay awake/i },
    { rank: 42, re: /screensaver/i },
    { rank: 43, re: /power profile/i }
  ]

  function rankFor(description) {
    for (var i = 0; i < root.priorityRules.length; i++) {
      if (root.priorityRules[i].re.test(description))
        return root.priorityRules[i].rank
    }
    return 999
  }

  // --- collection -------------------------------------------------------------

  // [{ shortcut, description, dispatcher, arg, mouse, actionable, searchText, rank }]
  property var rows: []
  property string query: ""
  property int selectedIndex: 0
  property string lastError: ""

  readonly property var filtered: {
    const q = root.query.trim().toLowerCase()
    if (q === "")
      return root.rows
    return root.rows.filter(r => r.searchText.indexOf(q) !== -1)
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

  function selectFirst() { root.selectedIndex = 0 }
  function selectLast() { root.selectedIndex = Math.max(0, root.filtered.length - 1) }

  function refresh() {
    collectorProc.running = true
  }

  Process {
    id: collectorProc
    command: [Quickshell.env("HOME") + "/.config/hypr/scripts/keybinds-collector"]
    stdout: StdioCollector { id: collectorOut }
    stderr: StdioCollector { id: collectorErr }
    onExited: function (code) {
      if (code === 0) {
        try {
          root.build(JSON.parse(collectorOut.text))
          root.lastError = ""
          return
        } catch (e) {
          // A corrupt/unreadable cache must never make the palette unavailable.
        }
      }
      bindsProc.running = true
    }
  }

  // Last-resort live path. It deliberately retains __lua registry references,
  // so activation keeps working even when replay or cache collection is absent.
  Process {
    id: bindsProc
    command: ["hyprctl", "binds", "-j"]
    stdout: StdioCollector { id: bindsOut }
    stderr: StdioCollector { id: bindsErr }
    onExited: function (code) {
      if (code !== 0) {
        const collectorMessage = collectorErr.text.trim()
        root.lastError = bindsErr.text.trim() || collectorMessage || "hyprctl binds failed"
        return
      }
      try {
        root.build(JSON.parse(bindsOut.text))
        root.lastError = ""
      } catch (e) {
        root.lastError = "Could not parse hyprctl binds: " + e
      }
    }
  }

  // --- normalisation ----------------------------------------------------------

  // Hyprland modmask bits. Emitted in a fixed order so the same combination
  // always renders identically.
  readonly property var modBits: [
    { bit: 64, name: "SUPER" },
    { bit: 1, name: "SHIFT" },
    { bit: 4, name: "CTRL" },
    { bit: 8, name: "ALT" }
  ]

  function modString(mask) {
    var parts = []
    for (var i = 0; i < root.modBits.length; i++) {
      if (mask & root.modBits[i].bit)
        parts.push(root.modBits[i].name)
    }
    return parts.join(" ")
  }

  // Keys that would otherwise render as an internal name or a bare symbol.
  readonly property var keyNames: ({
    "return": "RETURN",
    "kp_enter": "ENTER",
    "space": "SPACE",
    "escape": "ESCAPE",
    "tab": "TAB",
    "backspace": "BACKSPACE",
    "delete": "DELETE",
    "bracketleft": "[",
    "bracketright": "]",
    "comma": ",",
    "period": ".",
    "slash": "/",
    "backslash": "\\",
    "semicolon": ";",
    "apostrophe": "'",
    "grave": "`",
    "minus": "-",
    "equal": "=",
    "left": "LEFT",
    "right": "RIGHT",
    "up": "UP",
    "down": "DOWN",
    "print": "PRINT",
    "mouse_down": "SCROLL DOWN",
    "mouse_up": "SCROLL UP",
    "mouse:272": "LEFT CLICK",
    "mouse:273": "RIGHT CLICK",
    "mouse:274": "MIDDLE CLICK"
  })

  // The collector puts an active-XKB label on code binds when xkbcli is
  // available. This US/common-key table is the offline fallback; unknown codes
  // remain explicit rather than being guessed.
  readonly property var keycodeNames: ({
    9: "ESCAPE",
    10: "1", 11: "2", 12: "3", 13: "4", 14: "5",
    15: "6", 16: "7", 17: "8", 18: "9", 19: "0",
    20: "-", 21: "=", 22: "BACKSPACE", 23: "TAB",
    24: "Q", 25: "W", 26: "E", 27: "R", 28: "T", 29: "Y", 30: "U",
    31: "I", 32: "O", 33: "P", 34: "[", 35: "]", 36: "RETURN",
    38: "A", 39: "S", 40: "D", 41: "F", 42: "G", 43: "H", 44: "J",
    45: "K", 46: "L", 47: ";", 48: "'", 49: "`", 51: "\\",
    52: "Z", 53: "X", 54: "C", 55: "V", 56: "B", 57: "N", 58: "M",
    59: ",", 60: ".", 61: "/", 65: "SPACE",
    67: "F1", 68: "F2", 69: "F3", 70: "F4", 71: "F5", 72: "F6",
    73: "F7", 74: "F8", 75: "F9", 76: "F10", 95: "F11", 96: "F12",
    104: "ENTER", 110: "HOME", 111: "UP", 112: "PAGE UP", 113: "LEFT",
    114: "RIGHT", 115: "END", 116: "DOWN", 117: "PAGE DOWN",
    118: "INSERT", 119: "DELETE"
  })

  function keyLabel(bind) {
    const resolved = String(bind.key_label || "")
    if (resolved !== "")
      return resolved
    const raw = String(bind.key || "")
    if (raw === "") {
      const code = Number(bind.keycode || 0)
      const named = root.keycodeNames[code]
      return named !== undefined ? named : ("code:" + code)
    }

    const lower = raw.toLowerCase()
    if (root.keyNames[lower] !== undefined)
      return root.keyNames[lower]

    // XF86AudioRaiseVolume -> VOLUME UP, XF86MonBrightnessDown -> BRIGHTNESS DOWN
    if (lower.indexOf("xf86") === 0) {
      var rest = raw.substring(4).replace(/^Audio/, "").replace(/^Mon/, "")
      // Raise/Lower lead the noun ("RaiseVolume") where Up/Down trail it
      // ("BrightnessUp"), so the direction has to be moved to the end.
      const dir = rest.match(/^(Raise|Lower)(.+)$/)
      if (dir !== null)
        rest = dir[2] + (dir[1] === "Raise" ? " Up" : " Down")
      return rest.replace(/([a-z])([A-Z])/g, "$1 $2").toUpperCase()
    }

    return raw.toUpperCase()
  }

  // --- descriptions -----------------------------------------------------------

  readonly property var dispatcherNames: ({
    "killactive": "Close window",
    "exit": "Exit Hyprland",
    "togglefloating": "Toggle floating",
    "togglesplit": "Toggle split direction",
    "pseudo": "Toggle pseudotile",
    "fullscreen": "Fullscreen",
    "movefocus": "Move focus",
    "movewindow": "Move window",
    "swapwindow": "Swap window",
    "resizeactive": "Resize window",
    "resizewindow": "Resize window (drag)",
    "workspace": "Workspace",
    "movetoworkspace": "Move to workspace",
    "movetoworkspacesilent": "Move to workspace (silent)",
    "togglespecialworkspace": "Special workspace",
    "cyclenext": "Next window"
  })

  readonly property var directionNames: ({
    "l": "left", "r": "right", "u": "up", "d": "down"
  })

  // Only derives a label when the dispatcher makes one unambiguous. Anything
  // else falls back to the command itself rather than inventing a meaning.
  function describe(bind) {
    const desc = String(bind.description || "").trim()
    if (desc !== "")
      return desc

    const dispatcher = String(bind.dispatcher || "")
    const arg = String(bind.arg || "").trim()

    if (dispatcher === "exec") {
      if (arg === "")
        return "Run command"
      const first = arg.split(/\s+/)[0]
      // A bare command name reads as an app; a path reads as a script.
      if (first.indexOf("/") === -1 && !/[;&|$]/.test(arg))
        return "Launch " + first
      const base = first.substring(first.lastIndexOf("/") + 1)
      return "Run " + (base !== "" ? base : arg)
    }

    // `bindm` reports dispatcher "mouse" with the real action in the argument,
    // and takes no description syntax, so its label always comes from here.
    if (dispatcher === "mouse") {
      const mouseName = root.dispatcherNames[arg]
      return mouseName !== undefined ? mouseName : (arg !== "" ? arg : "Mouse binding")
    }

    const name = root.dispatcherNames[dispatcher]
    if (name === undefined)
      return dispatcher === "" ? "" : dispatcher

    if (arg === "")
      return name
    if (root.directionNames[arg] !== undefined)
      return name + " " + root.directionNames[arg]
    return name + " " + arg
  }

  // --- build ------------------------------------------------------------------

  // Dispatchers that must not fire from the palette: they would act the moment
  // the menu closes, and getting them wrong ends a session or a window.
  readonly property var noExecute: ["exit", "killactive"]

  // Longest merged "A / B" shortcut worth showing on one row; past this the two
  // bindings are listed separately. Sized against Theme.menuColumnMax.
  readonly property int mergeMaxLength: 32

  function build(binds) {
    if (!Array.isArray(binds)) {
      root.rows = []
      return
    }

    const seenKeys = ({})   // shortcut slot -> already taken
    const byAction = ({})   // dispatcher|arg -> index into list
    const list = []

    for (var i = 0; i < binds.length; i++) {
      const b = binds[i]
      const dispatcher = String(b.dispatcher || "")
      if (dispatcher === "")
        continue

      const isMouse = b.mouse === true
      const key = String(b.key || "")
      const slot = String(b.modmask || 0) + "|"
                 + (key !== "" ? key : "code:" + String(b.keycode || 0))

      // Hyprland honours the first bind registered for a slot, so later ones are
      // shadowed and would only show as phantom duplicates. This is what folds
      // away the doubled wpctl/pactl volume binds.
      if (seenKeys[slot])
        continue
      seenKeys[slot] = true

      const description = root.describe(b)
      if (description === "")
        continue

      const mods = root.modString(Number(b.modmask || 0))
      const keyName = root.keyLabel(b)
      const shortcut = mods === "" ? keyName : (mods + " + " + keyName)
      const arg = String(b.arg || "").trim()

      // Two shortcuts running exactly the same thing are one row with both
      // shortcuts. Matching descriptions alone never merge -- only identical
      // dispatcher and argument.
      // Replayed Lua actions now have stable dispatcher/argument identity.
      // Unrecovered __lua actions retain distinct registry IDs, so two actions
      // with the same description can never be fused accidentally.
      const actionKey = dispatcher + "|" + arg
      const existing = byAction[actionKey]
      if (existing !== undefined && !isMouse && !list[existing].mouse) {
        // When both use the same modifiers only the differing key is appended,
        // keeping the merged form short.
        const merged = list[existing].shortcut + " / "
          + (list[existing].mods === mods ? keyName : shortcut)
        // The shortcut column is sized from the longest entry, so a merge that
        // would not fit stays two rows rather than widening every other row.
        if (merged.length <= root.mergeMaxLength) {
          list[existing].shortcut = merged
          continue
        }
      }

      const row = {
        shortcut: shortcut,
        mods: mods,
        description: description,
        dispatcher: dispatcher,
        arg: arg,
        mouse: isMouse,
        // Mouse binds cannot be re-dispatched, and the denylist is deliberate.
        actionable: !isMouse && root.noExecute.indexOf(dispatcher) === -1,
        rank: root.rankFor(description),
        searchText: ""
      }
      byAction[actionKey] = list.length
      list.push(row)
    }

    // searchText is built last so it includes the merged alternate shortcuts.
    for (var j = 0; j < list.length; j++) {
      const r = list[j]
      r.searchText = (r.shortcut + " " + r.description + " "
                    + r.dispatcher + " " + r.arg).toLowerCase()
    }

    list.sort(function (a, b) {
      if (a.rank !== b.rank)
        return a.rank - b.rank
      return a.description.localeCompare(b.description)
    })

    root.rows = list
    if (root.selectedIndex >= root.filtered.length)
      root.selectedIndex = 0
  }

  // --- activation -------------------------------------------------------------

  // Closes first, then dispatches on the next tick, so window-relative
  // dispatchers act on the toplevel underneath instead of the dismissing overlay.
  function activate(row) {
    root.panelVisible = false
    if (!row || !row.actionable)
      return
    pending.row = row
    pending.restart()
  }

  Timer {
    id: pending
    property var row: null
    interval: 20
    repeat: false
    onTriggered: {
      const r = pending.row
      pending.row = null
      if (!r)
        return
      // Lua binds are exposed as __lua plus a registry reference. Hyprland
      // does not yet expose a public invoke-by-reference API, so validate the
      // numeric reference and contain the current registry lookup here.
      if (r.dispatcher === "__lua" && /^\d+$/.test(r.arg)) {
        const code = "local action = debug.getregistry()[" + r.arg + "]; "
                   + "assert(type(action) == 'function', 'invalid bind action'); action()"
        actionProc.command = ["hyprctl", "eval", code]
      } else if (r.dispatcher === "lua") {
        actionProc.command = ["hyprctl", "eval", r.arg]
      } else {
        actionProc.command = r.arg === ""
          ? ["hyprctl", "dispatch", r.dispatcher]
          : ["hyprctl", "dispatch", r.dispatcher, r.arg]
      }
      actionProc.running = true
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {}
    stderr: StdioCollector { id: actionErr }
    onExited: function (code) {
      if (code !== 0)
        console.warn("Keybinds: dispatch failed:", actionErr.text.trim())
    }
  }

  readonly property string glyphSearch: String.fromCodePoint(0xf0349) // md-magnify
}
