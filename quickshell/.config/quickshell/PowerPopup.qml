import QtQuick
import Quickshell
import Quickshell.Io

// Native power menu under the bar's power button. Actions run through the
// rofi powermenu launcher so lock/suspend/logout behaviour stays in one script.
PopupWindow {
  id: popup
  required property Item anchorItem

  visible: false
  grabFocus: true
  anchor.item: anchorItem
  anchor.edges: Edges.Bottom
  anchor.gravity: Edges.Bottom
  anchor.margins.top: Theme.gapS
  implicitWidth: Theme.fs(180)
  implicitHeight: body.implicitHeight + Theme.gapM * 2

  // Action awaiting a second click; "" when nothing is pending.
  property string confirming: ""

  readonly property var actions: [
    { id: "lock",     label: "Lock",     glyph: String.fromCodePoint(0xf033e), confirm: false },
    { id: "suspend",  label: "Sleep",    glyph: String.fromCodePoint(0xf0904), confirm: false },
    { id: "logout",   label: "Log out",  glyph: String.fromCodePoint(0xf0343), confirm: true },
    { id: "reboot",   label: "Reboot",   glyph: String.fromCodePoint(0xf0709), confirm: true },
    { id: "shutdown", label: "Shutdown", glyph: String.fromCodePoint(0xf0425), confirm: true }
  ]

  function pick(a) {
    if (a.confirm && popup.confirming !== a.id) { popup.confirming = a.id; return }
    popup.visible = false
    runner.command = ["bash", Quickshell.env("HOME") + "/.config/rofi/powermenu/launcher.sh", a.id]
    runner.running = true
  }

  Process { id: runner }

  Rectangle { anchors.fill: parent; color: Theme.bg }

  Item {
    id: content
    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: {
      if (popup.confirming !== "") popup.confirming = ""
      else popup.visible = false
    }

    Column {
      id: body
      anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
      anchors.margins: Theme.gapM
      spacing: Theme.gapXS

      Repeater {
        model: popup.actions
        delegate: Rectangle {
          required property var modelData
          readonly property bool pending: popup.confirming === modelData.id
          width: body.width
          height: Theme.fs(32)
          radius: Theme.radiusRow
          color: pending ? Theme.red : (hover.hovered ? Theme.surface : "transparent")

          Row {
            anchors.fill: parent
            anchors.leftMargin: Theme.gapS
            spacing: Theme.gapS
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.glyph
              color: pending ? Theme.bgDeep : Theme.text
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(15)
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: pending ? "Confirm " + modelData.label.toLowerCase() + "?" : modelData.label
              color: pending ? Theme.bgDeep : Theme.text
              font.family: Theme.uiFamily
              font.pixelSize: Theme.fs(13)
            }
          }

          HoverHandler { id: hover }
          MouseArea { anchors.fill: parent; onClicked: popup.pick(modelData) }
        }
      }
    }
  }

  onVisibleChanged: {
    popup.confirming = ""
    if (visible) content.forceActiveFocus()
  }
}
