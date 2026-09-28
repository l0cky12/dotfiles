import QtQuick
import Quickshell
import Quickshell.Wayland

// lmenu (Super+Shift+A): the data-driven settings and actions menu.
//
// It replaced a rofi menu and deliberately still looks exactly like it: the
// window, input plate and rows reproduce rofi/lmenu.rasi over comet-glass.rasi,
// through the launcher* tokens in Theme.qml, and each row is the same padded
// monospace line rofi was given. Unlike rofi it stays mapped in the shell
// between uses, so opening it is a visibility flip rather than a process
// start. All state lives in LmenuState.
//
// The layer covers the screen so it can take exclusive keyboard focus and close
// on a click outside the menu, as rofi does, but it draws nothing there: rofi
// never dimmed the desktop. It keeps clear of the bar's reserved zone, because
// rofi centred itself in the space below the bar, not on the whole monitor.
PanelWindow {
  id: panel
  required property string ownerScreen
  property var controller: LmenuState

  visible: panel.controller.panelVisible
        && panel.controller.panelScreen === panel.ownerScreen

  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Normal
  color: "transparent"

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.namespace: "quickshell-lmenu"

  FontMetrics {
    id: metrics
    font.family: Theme.glyphFamily
    font.pointSize: Theme.launcherFontPoints
  }

  // rofi's element box: padding and a 1px border around one line of text.
  readonly property int rowHeight:
    Math.ceil(metrics.height) + 2 * Theme.launcherRowPadV + 2
  // The search box can reach rows the view's own list never shows, so the list
  // allows the theme's ten lines for a query, bounded by the screen height.
  readonly property int availableLines: Math.max(0, Math.floor(
    (panel.height - 2 * Theme.launcherPadding - inputbar.height
      - Theme.launcherSpacing + Theme.launcherRowSpacing)
      / (panel.rowHeight + Theme.launcherRowSpacing)))
  readonly property int visibleLines: Math.min(panel.availableLines,
    Math.max(Theme.launcherLines, panel.controller.directRows.length))
  readonly property int shownRows:
    Math.min(panel.controller.filtered.length, panel.visibleLines)
  readonly property int listHeight: panel.shownRows === 0 ? 0
    : panel.shownRows * panel.rowHeight + (panel.shownRows - 1) * Theme.launcherRowSpacing

  function commit() {
    panel.controller.activate(panel.controller.selected)
  }

  // rofi's default highlight: every query word, bold and underlined, in the
  // row's text. Built as styled text, so the row text is escaped first, and
  // spaces become non-breaking: styled text collapses runs of spaces, which
  // would close up the padded suffix column.
  function escaped(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/ /g, "&nbsp;")
  }
  function highlighted(text, query) {
    const words = query.toLowerCase().split(/\s+/).filter(word => word !== "")
    if (words.length === 0)
      return panel.escaped(text)
    const marked = new Array(text.length).fill(false)
    const lower = text.toLowerCase()
    for (const word of words) {
      for (let at = lower.indexOf(word); at >= 0; at = lower.indexOf(word, at + word.length))
        marked.fill(true, at, at + word.length)
    }
    let out = ""
    let open = false
    for (let i = 0; i < text.length; i++) {
      if (marked[i] !== open) {
        out += marked[i] ? "<b><u>" : "</u></b>"
        open = marked[i]
      }
      out += panel.escaped(text[i])
    }
    return out + (open ? "</u></b>" : "")
  }

  Connections {
    target: panel.controller
    function onQueryReset() { search.text = "" }
  }

  // Clicking outside the menu closes it, as rofi's click-to-exit does.
  MouseArea {
    anchors.fill: parent
    onClicked: panel.controller.close()
  }

  Rectangle {
    id: window
    anchors.centerIn: parent
    width: Theme.launcherWidth
    height: 2 * Theme.launcherPadding + inputbar.height
            + (panel.listHeight > 0 ? Theme.launcherSpacing + panel.listHeight : 0)
    color: Theme.launcherBg0
    radius: Theme.launcherRadiusWindow
    border.width: Theme.borderWidth
    border.color: Theme.launcherWindowBorder

    // Swallows clicks inside the menu so they do not reach the close area.
    MouseArea { anchors.fill: parent }

    // --- inputbar: the view's name as the prompt, then the search entry ---
    Rectangle {
      id: inputbar
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Theme.launcherPadding
      height: Math.ceil(metrics.height) + 2 * Theme.launcherInputPadV
      radius: Theme.launcherRadiusInput
      color: Theme.launcherBg1

      Text {
        id: prompt
        anchors.left: parent.left
        anchors.leftMargin: Theme.launcherInputPadH
        anchors.verticalCenter: parent.verticalCenter
        text: panel.controller.title
        color: Theme.accent
        font: metrics.font
      }

      TextInput {
        id: search
        anchors.left: prompt.right
        anchors.leftMargin: Theme.launcherInputSpacing
        anchors.right: parent.right
        anchors.rightMargin: Theme.launcherInputPadH
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.launcherFg0
        font: metrics.font
        selectByMouse: true
        clip: true
        focus: true

        onTextChanged: panel.controller.query = text

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: search.text === ""
          text: panel.controller.lastError !== "" ? panel.controller.lastError
            : (panel.controller.loaded ? "Search…" : "Loading…")
          color: panel.controller.lastError !== "" ? Theme.error : Theme.launcherFg2
          font: metrics.font
          elide: Text.ElideRight
          width: search.width
        }

        Keys.onEscapePressed: panel.controller.close()
        Keys.onUpPressed: panel.controller.moveSelection(-1)
        Keys.onDownPressed: panel.controller.moveSelection(1)
        Keys.onReturnPressed: panel.commit()
        Keys.onEnterPressed: panel.commit()

        Keys.onPressed: event => {
          const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
          // Backspace edits the search while there is text to edit, and
          // walks back up the tree once the field is empty.
          if (event.key === Qt.Key_Backspace && search.text === "") {
            panel.controller.back(); event.accepted = true
          } else if (ctrl && event.key === Qt.Key_N) {
            panel.controller.moveSelection(1); event.accepted = true
          } else if (ctrl && event.key === Qt.Key_P) {
            panel.controller.moveSelection(-1); event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            panel.controller.moveSelection(panel.visibleLines); event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            panel.controller.moveSelection(-panel.visibleLines); event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            panel.controller.selectFirst(); event.accepted = true
          } else if (event.key === Qt.Key_End) {
            panel.controller.selectLast(); event.accepted = true
          }
        }
      }
    }

    // --- listview ---
    ListView {
      id: list
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: inputbar.bottom
      anchors.leftMargin: Theme.launcherPadding
      anchors.rightMargin: Theme.launcherPadding
      anchors.topMargin: Theme.launcherSpacing
      height: panel.listHeight
      spacing: Theme.launcherRowSpacing
      clip: true
      model: panel.controller.filtered
      currentIndex: panel.controller.selectedIndex
      // Arrow keys belong to the search field, which drives the selection.
      keyNavigationEnabled: false

      onCurrentIndexChanged: if (currentIndex >= 0)
        list.positionViewAtIndex(currentIndex, ListView.Contain)

      delegate: Rectangle {
        id: row
        required property var modelData
        required property int index
        readonly property bool isCurrent: index === panel.controller.selectedIndex
        // rofi's element states: a disabled row is its "urgent" state.
        readonly property bool urgent: row.modelData.disabled

        width: list.width
        height: panel.rowHeight
        radius: Theme.launcherRadiusRow
        color: row.isCurrent
          ? (row.urgent ? Theme.launcherSelectedUrgentBg : Theme.launcherSelectedBg)
          : row.urgent ? Theme.launcherUrgentBg
          : (row.index % 2 === 1 ? Theme.launcherAltBg : "transparent")
        border.width: 1
        border.color: row.isCurrent
          ? (row.urgent ? Theme.launcherSelectedUrgentBorder : Theme.launcherSelectedBorder)
          : (row.urgent ? Theme.launcherUrgentBorder : "transparent")

        Text {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: Theme.launcherRowPadH
          anchors.rightMargin: Theme.launcherRowPadH
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.StyledText
          text: panel.highlighted(panel.controller.display(row.modelData),
                                  panel.controller.query)
          color: row.isCurrent || row.urgent ? Theme.launcherFg0 : Theme.launcherFg1
          font: metrics.font
          elide: Text.ElideRight
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          // rofi's hover-select, but on real pointer movement only: the pointer
          // often already sits where the menu opens, and entered would yank the
          // selection off the top row before anything happened.
          onPositionChanged: panel.controller.selectedIndex = row.index
          onClicked: {
            panel.controller.selectedIndex = row.index
            panel.commit()
          }
        }
      }
    }
  }

  onVisibleChanged: {
    if (visible) {
      search.text = ""
      search.forceActiveFocus()
    }
  }
}
