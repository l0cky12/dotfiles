import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Row {
  id: root

  // Bar chrome scale, passed down from Bar.qml. Kept separate from Theme.fs so
  // the bar can be sized independently of the panels and of GTK text scaling.
  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }
  spacing: root.s(4)

  // Fixed 1-10 mapping. Not derived from Hyprland.workspaces (which only
  // lists workspaces that have actually been visited this session).
  // Glyph codepoints verified against the installed "JetBrainsMono Nerd
  // Font" cmap; svg entries are bundled brand icons (icons/*.svg).
  readonly property var slots: [
    { id: 1, glyph: "" },                 // fa-terminal
    { id: 2, svg: "icons/helium.svg" },
    { id: 3, svg: "icons/obsidian.svg" },
    { id: 4, glyph: "" },                 // custom-neovim
    { id: 5, glyph: "" },                 // fa-gamepad
    { id: 6, svg: "icons/qemu.svg" },
    { id: 7, glyph: "" },                 // cod-folder
    { id: 8, glyph: "" },                 // fa-telegram
    { id: 9, glyph: "" },                 // fa-spotify
    { id: 10, glyph: "" }                 // fa-terminal
  ]

  Repeater {
    model: root.slots

    Rectangle {
      id: cell
      width: root.s(26)
      height: root.s(26)
      radius: root.s(5)
      readonly property bool isFocused: Hyprland.focusedWorkspace !== null
                                         && Hyprland.focusedWorkspace.id === modelData.id
      // A workspace is in use when Hyprland reports at least one window on it.
      readonly property bool isOccupied: {
        const all = Hyprland.workspaces ? Hyprland.workspaces.values : []
        for (let i = 0; i < all.length; i++) {
          if (all[i].id === modelData.id)
            return all[i].toplevels ? all[i].toplevels.values.length > 0 : false
        }
        return false
      }
      // Empty workspaces are hidden; the Row closes the gap they leave. Until
      // Hyprland has reported a focused workspace (startup, or no IPC) nothing
      // is known, so every slot stays visible rather than collapsing the island.
      visible: isFocused || isOccupied || Hyprland.focusedWorkspace === null
      // Theme roles rather than fixed colours, so the icons read on light
      // themes as well as dark ones.
      readonly property color iconColor: isFocused ? Theme.onAccent : Theme.text
      color: isFocused ? Theme.accent : "transparent"

      Text {
        visible: modelData.glyph !== undefined
        anchors.centerIn: parent
        text: modelData.glyph !== undefined ? modelData.glyph : ""
        font.family: Theme.glyphFamily
        font.pixelSize: root.s(15)
        color: cell.iconColor
      }

      // The bundled SVGs are single-colour with a fixed light fill, which
      // disappears on a light bar. Read each one once and repaint its fill with
      // the same theme colour the glyphs use.
      FileView {
        id: svgFile
        path: modelData.svg !== undefined
              ? Qt.resolvedUrl(modelData.svg).toString().replace(/^file:\/\//, "")
              : ""
        printErrors: false
        property string svgText: ""
        onLoaded: svgText = text()
      }

      Image {
        visible: modelData.svg !== undefined
        anchors.centerIn: parent
        width: root.s(15)
        height: root.s(15)
        sourceSize: Qt.size(width, height)
        source: svgFile.svgText === "" ? ""
                : "data:image/svg+xml;utf8," + encodeURIComponent(
                    svgFile.svgText.replace(/fill="#[0-9a-fA-F]{3,8}"/g,
                                            'fill="' + cell.iconColor + '"'))
        smooth: true
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        // Hyprland 0.55+ evaluates dispatches as Lua expressions. Quickshell
        // wraps this in hl.dispatch(...), so the expression must be an
        // hl.dsp dispatcher rather than the old "workspace N" text command.
        onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + modelData.id + "\" })")
      }
    }
  }
}
