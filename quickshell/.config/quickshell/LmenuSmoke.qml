import Quickshell
import QtQuick

// Headless fixture for the resident lmenu. tests/lmenu-quickshell.test.sh
// points LMENU_MENU at a fixture tree, so this drives the real pipeline:
// lmenu-parse.py dump, then LmenuState's navigation, search and launching.
// The panel needs a Wayland backend to compile, so LmenuPanelSmoke.qml checks
// it separately and this file runs offscreen.
Scope {
  id: smoke
  property int failures: 0
  property var launched: []
  property int resets: 0
  property bool ran: false

  Connections {
    target: LmenuState
    function onQueryReset() { smoke.resets += 1 }
  }

  function check(name, condition) {
    if (condition)
      console.log("ok   " + name)
    else {
      console.log("FAIL " + name)
      failures += 1
    }
  }

  function ids(rows) { return rows.map(row => row.id).join(" ") }

  function search(text) {
    LmenuState.query = text
    return LmenuState.filtered
  }

  function run() {
    const state = LmenuState
    state.launch = command => smoke.launched.push(command)

    // An empty search shows the view's own rows and nothing nested.
    check("root shows only its own rows", ids(state.filtered) === "s link")
    check("root title", state.title === "Menu")
    check("submenus carry a chevron", state.filtered[0].suffix === state.chevron)
    // Rows are the same padded monospace lines the rofi menu drew.
    check("direct rows pad their suffix into one column",
          state.display(state.filtered[0]) === "Section      ›"
          && state.display(state.filtered[1]) === "Jump to Sub  ›")

    // Typing reaches every level below, each result with its breadcrumb.
    let rows = search("deep")
    check("search finds a row two levels down",
          rows.length === 1 && rows[0].id === "s.sub.deep")
    check("a nested result names the menus above it",
          rows.length === 1 && rows[0].crumb === "Section / Sub")
    check("a nested row trails its breadcrumb",
          state.display(rows[0]) === "Deep   Section / Sub")
    check("search matches hidden aliases", ids(search("buried")) === "s.sub.deep")
    check("search matches descriptions", ids(search("two levels")) === "s.sub.deep")
    check("every word of the query must match", ids(search("deep nothing")) === "")
    check("search is case-insensitive", ids(search("DEEP")) === "s.sub.deep")
    check("search matches breadcrumbs", search("sub").some(row => row.id === "s.sub.deep"))
    check("rows behind a failing guard stay unreachable",
          search("orphaned").length === 0 && search("gone").length === 0)
    check("rows below a dimmed row stay unreachable", search("unreachable").length === 0)
    check("a dimmed row itself is still listed", search("dim").some(row => row.id === "s.dim"))
    check("the view's own matches come before nested ones",
          ids(search("s")).indexOf("s link ") === 0)
    check("font rows are not searched from above",
          state.nestedRows.every(row => row.id.indexOf("s.fonts#") !== 0))

    // Navigation.
    search("")
    const resetsBefore = smoke.resets
    state.activate(state.filtered.find(row => row.id === "s"))
    check("activating a submenu opens it", state.route === "s")
    check("opening a view clears the search",
          state.query === "" && smoke.resets === resetsBefore + 1)
    check("a submenu shows its own rows", ids(state.filtered) === "s.sub s.dim s.fonts s.leaf")
    check("a submenu is titled by its entry", state.title === "Section")

    state.activate(state.filtered.find(row => row.id === "s.dim"))
    check("a dimmed row does nothing", state.route === "s" && smoke.launched.length === 0)

    state.panelScreen = "smoke"
    state.panelVisible = true
    state.activate(state.filtered.find(row => row.id === "s.leaf"))
    check("a leaf launches its action", smoke.launched.join("|") === "echo leaf")
    check("launching a leaf closes the menu", !state.panelVisible)

    state.enter("")
    state.activate(state.filtered.find(row => row.id === "link"))
    check("a link opens its target", state.route === "s.sub")

    state.back()
    check("back goes up one level", state.route === "s")
    state.back()
    check("back reaches the root", state.route === "")
    state.panelVisible = true
    state.back()
    check("back at the root closes the menu", !state.panelVisible)

    // A nested submenu picked from search opens at its own route.
    state.enter("")
    search("sub")
    state.activate(state.filtered.find(row => row.id === "s.sub"))
    check("a nested submenu opens where it lives", state.route === "s.sub")

    state.enter("s.fonts")
    check("a provider view lists its generated rows",
          state.filtered.length > 0 && state.filtered.every(row => row.kind === "leaf"))

    check("aliases resolve to their entry", state.resolveRoute("Nested_Menu") === "s.sub")
    check("root names resolve to the root", state.resolveRoute("menu") === "")

    // Toggling on the same screen closes; summoning resets to the route.
    state.summon("smoke", "nested-menu")
    check("summon opens at an alias", state.panelVisible && state.route === "s.sub")
    state.toggle("smoke", "")
    check("toggle on the same screen closes", !state.panelVisible)

    // A refresh keeps the user's place.
    state.enter("s")
    state.selectedIndex = 3
    state.load({ entries: Object.keys(state.byId).map(id => state.byId[id]),
                 providers: state.generated, aliases: state.aliases })
    check("a refresh keeps the selected row", state.selected && state.selected.id === "s.leaf")

    console.log(smoke.failures === 0
      ? "ok: lmenu resident menu"
      : "FAIL: " + smoke.failures + " assertion(s) failed")
    Qt.quit()
  }

  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (LmenuState.loaded && !smoke.ran) {
        smoke.ran = true
        smoke.run()
      } else if (LmenuState.lastError !== "") {
        console.log("FAIL: " + LmenuState.lastError)
        Qt.quit()
      }
    }
  }

  Timer {
    interval: 10000
    running: true
    onTriggered: {
      console.log("FAIL: lmenu smoke test timed out")
      Qt.quit()
    }
  }
}
