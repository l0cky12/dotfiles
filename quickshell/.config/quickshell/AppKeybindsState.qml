pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Display-only keybinding palette for programs whose live mappings are owned
// outside Hyprland. application-keybinds reads local state every time this is
// opened; no web documentation or baked-in key list is used.
Singleton {
  id: root

  property bool panelVisible: false
  property string panelScreen: ""
  property string source: ""
  property string title: "Application keybindings"
  property var rows: []
  property string query: ""
  property int selectedIndex: 0
  property string lastError: ""

  readonly property var filtered: {
    const q = root.query.trim().toLowerCase()
    return q === "" ? root.rows : root.rows.filter(r => r.searchText.indexOf(q) !== -1)
  }
  readonly property var selected:
    selectedIndex >= 0 && selectedIndex < filtered.length ? filtered[selectedIndex] : null

  function togglePanel(screenName, requestedSource) {
    if (panelVisible && panelScreen === screenName && source === requestedSource) {
      close()
      return
    }
    if (screenName === "")
      return
    source = requestedSource
    panelScreen = screenName
    panelVisible = true
    refresh()
  }

  function close() { panelVisible = false }
  function moveSelection(delta) {
    const count = filtered.length
    if (count > 0)
      selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + delta))
  }
  function selectFirst() { selectedIndex = 0 }
  function selectLast() { selectedIndex = Math.max(0, filtered.length - 1) }
  // These rows describe another application's input; Enter never replays it.
  function activate(row) { close() }

  function refresh() { collector.running = true }

  Process {
    id: collector
    command: [Quickshell.env("HOME") + "/.config/hypr/scripts/application-keybinds", root.source]
    stdout: StdioCollector { id: output }
    stderr: StdioCollector { id: errors }
    onExited: function(code) {
      if (code !== 0) {
        root.rows = []
        root.lastError = errors.text.trim() || "Could not collect local keybindings"
        return
      }
      try {
        const result = JSON.parse(output.text)
        root.title = String(result.title || "Application keybindings")
        root.rows = Array.isArray(result.rows) ? result.rows : []
        root.lastError = String(result.error || "")
        root.selectedIndex = 0
      } catch (error) {
        root.rows = []
        root.lastError = "Could not parse local keybindings: " + error
      }
    }
  }
}
