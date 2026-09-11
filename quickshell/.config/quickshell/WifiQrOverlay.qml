pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

// Centered "Share Wi-Fi" QR overlay.
//
// The QR used to live inside NetworkPanel, which is a bar-anchored
// PopupWindow, so the code appeared in the top-right corner. Scanning a
// code wants the whole screen, so it now gets its own fullscreen
// layer-shell overlay shaped like the other centred surfaces in this
// shell (KeybindsPanel / ThemePicker / WebAppPanel): one instance per
// monitor, only the one matching NetworkState.overlayScreen visible,
// overlay layer so it covers the bar, exclusive keyboard focus, no
// space reserved.
//
// The QR itself stays in NetworkState -- this window only renders it.
// Dismissal is deliberate only: Escape, a click on the scrim, or the
// Back button. There is no auto-close timer, because someone holding a
// phone up to the screen should never race one.
PanelWindow {
  id: panel

  required property string ownerScreen

  visible: NetworkState.qrResult !== null
        && NetworkState.overlayScreen === panel.ownerScreen

  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.namespace: "quickshell-wifi-qr"

  // Clearing qrResult is both the dismissal and the close; the panel-side
  // connection only acts on it being set, so this can never reopen it.
  function close() {
    NetworkState.qrResult = null
  }

  // -- scrim -----------------------------------------------------------------
  // Same confirm-dialog vocabulary: Theme.scrimOpacity over the theme bg.
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, Theme.scrimOpacity)

    // Clicking outside the card dismisses the overlay.
    MouseArea {
      anchors.fill: parent
      onClicked: panel.close()
    }
  }

  // -- card ------------------------------------------------------------------
  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Theme.fs(360)
    height: qrContent.implicitHeight + Theme.gapL * 2
    radius: Theme.radiusM
    color: Theme.bg
    border.width: Math.max(1, Theme.borderWidth)
    border.color: Theme.borderAccent

    // Swallows clicks so they do not reach the dismissing scrim.
    MouseArea { anchors.fill: parent }

    FocusScope {
      id: keys
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: panel.close()

      Column {
        id: qrContent
        anchors.centerIn: parent
        spacing: Theme.gapM

        Text {
          text: "Share Wi-Fi"
          color: Theme.text
          font.bold: true
          font.pixelSize: Theme.fs(17)
          anchors.horizontalCenter: parent.horizontalCenter
        }

        Image {
          source: NetworkState.qrResult ? "file://" + NetworkState.qrResult.path : ""
          width: Theme.fs(280)
          height: Theme.fs(280)
          fillMode: Image.PreserveAspectFit
          sourceSize.width: width
          sourceSize.height: height
          anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
          text: NetworkState.qrResult ? NetworkState.qrResult.ssid : ""
          color: Theme.text
          font.pixelSize: Theme.fs(14)
          anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
          text: NetworkState.qrResult ? NetworkState.qrResult.security : ""
          color: Theme.textDim
          font.pixelSize: Theme.fs(11)
          anchors.horizontalCenter: parent.horizontalCenter
        }

        Rectangle {
          width: Theme.fs(82)
          height: Theme.fs(28)
          radius: Theme.radiusCell
          color: Theme.surface
          anchors.horizontalCenter: parent.horizontalCenter

          Text {
            anchors.centerIn: parent
            text: "Back"
            color: Theme.text
            font.pixelSize: Theme.fs(10)
          }

          MouseArea {
            anchors.fill: parent
            onClicked: panel.close()
          }
        }
      }
    }
  }

  onVisibleChanged: if (visible) keys.forceActiveFocus()
}
