pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// lmenu (Super+Shift+A), resident in the shell so opening it never waits on a
// process.
//
// ~/.config/lmenu/menu.jsonc stays the only definition of the tree, and
// lmenu-parse.py the only code that understands it: `lmenu-parse.py dump`
// evaluates every guard and provider and hands back the reachable tree as
// JSON. This singleton keeps the last dump in memory, draws from it
// immediately, and re-runs the dump in the background each time the menu
// opens, so ticks and hidden rows catch up within half a second.
//
// An empty search shows the current view's own rows. Typing searches every
// row below the view as well, each nested row carrying the menus it lives
// under, so a setting can be found without knowing where it sits.
Singleton {
  id: root

  property bool panelVisible: false
  property string panelScreen: ""
  property string route: ""
  property string query: ""
  property int selectedIndex: 0
  property bool loaded: false
  property string lastError: ""

  // Emitted when the view changes under the search field, which has to clear
  // its text; the field owns the text, so the state cannot just assign it.
  signal queryReset()

  // --- snapshot, rebuilt by load() -------------------------------------------
  property var byId: ({})
  property var childrenOf: ({})
  property var generated: ({})
  property var aliases: ({})

  readonly property string configHome:
    Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
  property string parserPath:
    Quickshell.env("LMENU_PARSER") || (root.configHome + "/lmenu/lmenu-parse.py")
  // Tests swap this for a recorder so activating a leaf launches nothing.
  property var launch: function (command) {
    Quickshell.execDetached(["bash", "-c", command])
  }

  readonly property string check: "✓"
  readonly property string chevron: "›"
  readonly property string crumbSeparator: " / "

  function load(doc) {
    const byId = {}
    const childrenOf = { "": [] }
    const entries = Array.isArray(doc.entries) ? doc.entries : []
    for (const entry of entries) {
      byId[entry.id] = entry
      if (!childrenOf[entry.parent])
        childrenOf[entry.parent] = []
      childrenOf[entry.parent].push(entry)
    }
    const selectedId = root.selected ? root.selected.id : ""
    root.byId = byId
    root.childrenOf = childrenOf
    root.generated = doc.providers || {}
    root.aliases = doc.aliases || {}
    root.loaded = true
    root.lastError = ""
    // A refresh landing while the menu is open must not move the selection
    // off the row the user is on.
    const kept = root.filtered.findIndex(row => row.id === selectedId)
    root.selectedIndex = kept >= 0 ? kept
      : Math.max(0, Math.min(root.selectedIndex, root.filtered.length - 1))
  }

  // --- routes ----------------------------------------------------------------
  function normalise(value) {
    return String(value).trim().toLowerCase().replace(/_/g, "-")
  }

  // The same rules as lmenu-parse.py: the root has several names, an id is
  // itself, an alias maps to its id, and anything else is taken literally.
  function resolveRoute(value) {
    const name = String(value || "").trim()
    if (name === "" || name === "menu" || name === "go" || name === "root")
      return ""
    if (root.byId[name])
      return name
    return root.aliases[root.normalise(name)] || name
  }

  function parentOf(id) {
    const dot = id.lastIndexOf(".")
    return dot < 0 ? "" : id.slice(0, dot)
  }

  readonly property string title: {
    if (root.route === "")
      return "Menu"
    const entry = root.byId[root.route]
    return entry ? entry.title : root.route
  }

  // --- rows ------------------------------------------------------------------
  function entryRow(entry, crumb) {
    const descends = entry.kind === "submenu" || entry.kind === "link"
      || entry.kind === "provider"
    // A tick outranks a chevron, and a nested row shows its breadcrumb in
    // place of one, as the rofi front end did.
    const suffix = (entry.checked || entry.disabled) ? root.check
      : (descends && crumb === "" ? root.chevron : "")
    return {
      id: entry.id, icon: entry.icon, label: entry.label, suffix: suffix,
      crumb: crumb, kind: entry.kind, payload: entry.payload,
      disabled: entry.disabled,
      haystack: (entry.label + " " + crumb + " " + entry.search).toLowerCase()
    }
  }

  function generatedRow(row, crumb) {
    return {
      id: row.id, icon: row.icon, label: row.label,
      suffix: row.checked ? root.check : "", crumb: crumb,
      kind: "leaf", payload: row.payload, disabled: false,
      haystack: (row.label + " " + crumb + " " + row.search).toLowerCase()
    }
  }

  readonly property bool providerView:
    !!root.byId[root.route] && root.byId[root.route].kind === "provider"

  readonly property var directRows: {
    if (root.providerView)
      return (root.generated[root.route] || []).map(row => root.generatedRow(row, ""))
    return (root.childrenOf[root.route] || []).map(entry => root.entryRow(entry, ""))
  }

  // Everything below the direct rows in tree order. Provider rows join only
  // where the provider is marked searchable: fonts and timezones would bury
  // every setting under hundreds of matches.
  readonly property var nestedRows: {
    const rows = []
    if (root.providerView)
      return rows
    function walk(parent, trail) {
      for (const entry of (root.childrenOf[parent] || [])) {
        if (trail.length > 0)
          rows.push(root.entryRow(entry, trail.join(root.crumbSeparator)))
        const below = trail.concat([entry.label])
        if (entry.searchable) {
          for (const row of (root.generated[entry.id] || []))
            rows.push(root.generatedRow(row, below.join(root.crumbSeparator)))
        }
        walk(entry.id, below)
      }
    }
    walk(root.route, [])
    return rows
  }

  // Every word of the query has to appear somewhere in a row's label,
  // breadcrumb or hidden search terms, matching rofi's default tokenising.
  readonly property var filtered: {
    const words = root.query.toLowerCase().split(/\s+/).filter(word => word !== "")
    if (words.length === 0)
      return root.directRows
    const matches = row => words.every(word => row.haystack.includes(word))
    return root.directRows.filter(matches).concat(root.nestedRows.filter(matches))
  }

  // Width of the widest direct label, so the suffix column clears every row.
  readonly property int labelPad:
    root.directRows.reduce((widest, row) => Math.max(widest, row.label.length), 0)

  // The exact line the rofi front end drew: "icon  label  ›", with suffixes
  // padded into a column of their own. That only lines up because the font is
  // monospace. A nested row trails its breadcrumb instead of joining the column.
  function display(row) {
    const icon = row.icon ? row.icon + "  " : ""
    if (row.crumb !== "")
      return icon + row.label + "   " + row.crumb + (row.suffix ? "  " + row.suffix : "")
    if (row.suffix)
      return icon + row.label.padEnd(root.labelPad) + "  " + row.suffix
    return icon + row.label
  }

  readonly property var selected:
    (selectedIndex >= 0 && selectedIndex < filtered.length) ? filtered[selectedIndex] : null

  onQueryChanged: root.selectedIndex = 0

  function moveSelection(delta) {
    const count = root.filtered.length
    if (count === 0)
      return
    root.selectedIndex = Math.max(0, Math.min(count - 1, root.selectedIndex + delta))
  }
  function selectFirst() { root.selectedIndex = 0 }
  function selectLast() { root.selectedIndex = Math.max(0, root.filtered.length - 1) }

  // --- navigation ------------------------------------------------------------
  function enter(route) {
    root.route = route
    root.query = ""
    root.selectedIndex = 0
    root.queryReset()
  }

  function activate(row) {
    if (!row || row.disabled)
      return
    if (row.kind === "leaf") {
      root.close()
      root.launch(row.payload)
    } else if (row.kind === "link") {
      root.enter(row.payload)
    } else {
      root.enter(row.id)
    }
  }

  // Backspace on an empty search: up one level, or closed from the root.
  function back() {
    if (root.route === "")
      root.close()
    else
      root.enter(root.parentOf(root.route))
  }

  function summon(screenName, route) {
    if (screenName === "")
      return
    root.panelScreen = screenName
    root.enter(root.resolveRoute(route))
    root.panelVisible = true
    root.refresh()
  }

  function toggle(screenName, route) {
    if (root.panelVisible && root.panelScreen === screenName) {
      root.close()
      return
    }
    root.summon(screenName, route)
  }

  function close() {
    root.panelVisible = false
  }

  // --- refresh ---------------------------------------------------------------
  property bool refreshQueued: false

  function refresh() {
    if (dumpProc.running) {
      root.refreshQueued = true
      return
    }
    dumpProc.running = true
  }

  Process {
    id: dumpProc
    command: ["python3", root.parserPath, "dump"]
    stdout: StdioCollector { id: dumpOut }
    stderr: StdioCollector { id: dumpErr }
    onExited: function (code) {
      let problem = ""
      if (code === 0) {
        try {
          root.load(JSON.parse(dumpOut.text))
        } catch (error) {
          problem = "lmenu: unreadable menu dump: " + error
        }
      } else {
        problem = dumpErr.text.trim() || ("lmenu-parse.py dump exited " + code)
      }
      if (problem !== "") {
        console.warn(problem)
        // A stale menu beats no menu: only surface the error when there is
        // nothing cached to show.
        if (!root.loaded)
          root.lastError = problem
      }
      if (root.refreshQueued) {
        root.refreshQueued = false
        dumpProc.running = true
      }
    }
  }

  // Warm the cache at shell start, so even the first open draws at once.
  Component.onCompleted: root.refresh()
}
