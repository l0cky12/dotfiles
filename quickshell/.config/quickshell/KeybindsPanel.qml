import QtQuick
import Quickshell
import Quickshell.Wayland

// Centred keybindings palette (Super+K).
//
// Unlike the other panels this is a fullscreen layer-shell overlay rather than a
// bar-anchored PopupWindow: it needs to dim the whole desktop behind a centred
// card, which an anchored popup cannot do. It sits on the overlay layer so it
// covers the bar too, and takes exclusive keyboard focus so typing goes to the
// search field rather than to the window underneath.
//
// Every dimension and colour weight comes from the menu* tokens in Theme.qml.
PanelWindow {
  id: panel
  required property string ownerScreen

  visible: KeybindsState.panelVisible
        && KeybindsState.panelScreen === panel.ownerScreen

  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.namespace: "quickshell-keybinds"

  // The card is a fixed target size, clamped to the screen so it still fits on a
  // rotated or small monitor instead of running off the edge.
  readonly property int availWidth: panel.width - 2 * Theme.menuOuterMargin
  readonly property int availHeight: panel.height - 2 * Theme.menuOuterMargin
  readonly property int cardWidth: Math.min(Theme.menuWidth, panel.availWidth)

  readonly property int chromeHeight:
    2 * Theme.menuPadding + Theme.menuHeaderHeight + Theme.gapM + 1 + Theme.gapS
  readonly property int listHeight:
    KeybindsState.filtered.length * Theme.menuRowHeight
  readonly property int cardHeight:
    Math.min(Theme.menuMaxHeight, panel.availHeight,
             panel.chromeHeight + Math.max(Theme.menuRowHeight, panel.listHeight))

  // Monospace, so the longest shortcut by character count is the widest one.
  readonly property string longestShortcut: {
    var best = ""
    const rows = KeybindsState.filtered
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].shortcut.length > best.length)
        best = rows[i].shortcut
    }
    return best
  }

  TextMetrics {
    id: columnMetrics
    font.family: Theme.glyphFamily
    font.pixelSize: Theme.menuFontBody
    text: panel.longestShortcut
  }

  // Clamped so a single very long shortcut cannot push the descriptions off the
  // card, and a short list cannot bunch the arrows against the left edge.
  readonly property int shortcutColumn:
    Math.max(Theme.menuColumnMin,
             Math.min(Theme.menuColumnMax, Math.ceil(columnMetrics.width)))

  function commit() {
    KeybindsState.activate(KeybindsState.selected)
  }

  // --- scrim ---
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, Theme.menuScrimOpacity)

    MouseArea {
      anchors.fill: parent
      onClicked: KeybindsState.close()
    }
  }

  // --- card, with the compositor's own active-border gradient as its frame ---
  Rectangle {
    id: frame
    anchors.centerIn: parent
    width: panel.cardWidth
    height: panel.cardHeight
    radius: Theme.menuRadius

    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: Theme.borderActive1 }
      GradientStop { position: 1.0; color: Theme.borderActive2 }
    }

    // Swallows clicks on the card so they do not reach the scrim's dismiss area.
    MouseArea { anchors.fill: parent }

    Rectangle {
      anchors.fill: parent
      anchors.margins: Theme.menuBorderWidth
      radius: Math.max(0, Theme.menuRadius - Theme.menuBorderWidth)
      color: Theme.bg

      Item {
        anchors.fill: parent
        anchors.margins: Theme.menuPadding

        // --- header / search ---
        Item {
          id: header
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: Theme.menuHeaderHeight

          TextInput {
            id: search
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.menuFontTitle
            selectByMouse: true
            clip: true
            focus: true

            onTextChanged: KeybindsState.query = text

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: search.text === ""
              text: "Keybindings…"
              color: Theme.textMuted
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.menuFontTitle
            }

            Keys.onEscapePressed: KeybindsState.close()
            Keys.onUpPressed: KeybindsState.moveSelection(-1)
            Keys.onDownPressed: KeybindsState.moveSelection(1)
            Keys.onReturnPressed: panel.commit()
            Keys.onEnterPressed: panel.commit()

            // Emacs-style navigation and paging, kept off the plain letter keys
            // so ordinary typing always reaches the search field.
            Keys.onPressed: event => {
              const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
              if (ctrl && event.key === Qt.Key_N) {
                KeybindsState.moveSelection(1); event.accepted = true
              } else if (ctrl && event.key === Qt.Key_P) {
                KeybindsState.moveSelection(-1); event.accepted = true
              } else if (event.key === Qt.Key_PageDown) {
                KeybindsState.moveSelection(10); event.accepted = true
              } else if (event.key === Qt.Key_PageUp) {
                KeybindsState.moveSelection(-10); event.accepted = true
              } else if (event.key === Qt.Key_Home) {
                KeybindsState.selectFirst(); event.accepted = true
              } else if (event.key === Qt.Key_End) {
                KeybindsState.selectLast(); event.accepted = true
              }
            }
          }
        }

        Rectangle {
          id: divider
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: header.bottom
          anchors.topMargin: Theme.gapM
          height: 1
          color: Theme.surface
        }

        // --- status (errors / no matches) ---
        Text {
          id: status
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: divider.bottom
          anchors.topMargin: Theme.gapS
          visible: text !== ""
          wrapMode: Text.WordWrap
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.menuFontBody
          color: KeybindsState.lastError !== "" ? Theme.error : Theme.textMuted
          text: {
            if (KeybindsState.lastError !== "")
              return KeybindsState.lastError
            if (KeybindsState.rows.length === 0)
              return "No keybindings found"
            if (KeybindsState.filtered.length === 0)
              return "No bindings match “" + KeybindsState.query + "”"
            return ""
          }
        }

        // --- rows ---
        ListView {
          id: list
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: status.visible ? status.bottom : divider.bottom
          anchors.bottom: parent.bottom
          anchors.topMargin: Theme.gapS
          clip: true
          model: KeybindsState.filtered
          currentIndex: KeybindsState.selectedIndex
          // Driven from the search field, so the list must not steal keys.
          interactive: true
          keyNavigationEnabled: false

          onCurrentIndexChanged: if (currentIndex >= 0)
            list.positionViewAtIndex(currentIndex, ListView.Contain)

          delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool isCurrent: index === KeybindsState.selectedIndex

            width: list.width
            height: Theme.menuRowHeight
            radius: Theme.menuRadius
            color: isCurrent
              ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, Theme.menuSelectedAlpha)
              : "transparent"
            border.width: Theme.borderWidth
            border.color: isCurrent
              ? Qt.rgba(Theme.borderActive1.r, Theme.borderActive1.g,
                        Theme.borderActive1.b, Theme.menuBorderAlpha)
              : "transparent"

            Text {
              id: shortcut
              anchors.left: parent.left
              anchors.leftMargin: Theme.gapM
              anchors.verticalCenter: parent.verticalCenter
              width: panel.shortcutColumn
              text: row.modelData.shortcut
              color: row.isCurrent ? Theme.accent : Theme.text
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.menuFontBody
              elide: Text.ElideRight
            }

            Text {
              id: arrow
              anchors.left: shortcut.right
              anchors.leftMargin: Theme.gapM
              anchors.verticalCenter: parent.verticalCenter
              text: "→"
              color: row.modelData.actionable
                ? (row.isCurrent ? Theme.accent : Theme.textMuted)
                : Theme.textMuted
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.menuFontBody
            }

            Text {
              anchors.left: arrow.right
              anchors.leftMargin: Theme.gapM
              anchors.right: parent.right
              anchors.rightMargin: Theme.gapM
              anchors.verticalCenter: parent.verticalCenter
              text: row.modelData.description
              color: row.isCurrent ? Theme.accent : Theme.textDim
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.menuFontBody
              elide: Text.ElideRight
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Theme.gapS
              anchors.verticalCenter: parent.verticalCenter
              visible: !row.modelData.actionable
              text: "→"
              color: Theme.textFaint
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.menuFontBody
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              // Deliberately not onEntered: the pointer is usually already
              // sitting over the list when the palette opens, and entered fires
              // for whatever row lands under it, yanking the selection off the
              // top result before the user has done anything. Only real pointer
              // movement takes the selection.
              onPositionChanged: KeybindsState.selectedIndex = row.index
              onClicked: {
                KeybindsState.selectedIndex = row.index
                panel.commit()
              }
            }
          }
        }
      }
    }
  }

  onVisibleChanged: {
    if (visible) {
      search.text = ""
      KeybindsState.query = ""
      KeybindsState.selectedIndex = 0
      search.forceActiveFocus()
    }
  }
}
