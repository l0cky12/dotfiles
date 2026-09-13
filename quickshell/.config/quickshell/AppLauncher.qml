import QtQuick
import Quickshell
import Quickshell.Io

// Pinned applications are configured in app-launcher.json. A click focuses an
// existing Hyprland window by its configured class, or launches the desktop
// entry if it is not running. Hovering reveals the app name below the bar.
Row {
  id: root

  property real barScale: 1.0
  property var apps: []
  function s(n) { return Theme.fs(n * root.barScale) }

  function validApp(value) {
    if (!value || typeof value !== "object") return null
    const desktopId = String(value.desktopId || "")
    const name = String(value.name || "")
    const icon = String(value.icon || "")
    const wmClass = String(value.wmClass || "")
    if (!/^[A-Za-z0-9_.-]+$/.test(desktopId)
        || !/^[A-Za-z0-9_.-]+$/.test(wmClass)
        || name.length === 0 || icon.length === 0)
      return null
    return { desktopId: desktopId, name: name, icon: icon, wmClass: wmClass }
  }

  FileView {
    id: configFile
    path: Qt.resolvedUrl("app-launcher.json")
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        const parsed = JSON.parse(text())
        const configured = Array.isArray(parsed.apps) ? parsed.apps : []
        root.apps = configured.map(root.validApp).filter(function(app) { return app !== null })
      } catch (error) {
        console.warn("app launcher: invalid app-launcher.json:", error)
        root.apps = []
      }
    }
    onLoadFailed: function(error) {
      console.warn("app launcher: could not load app-launcher.json:", error)
      root.apps = []
    }
  }

  Repeater {
    model: root.apps

    Item {
      id: appItem
      required property var modelData
      readonly property var app: modelData
      implicitWidth: root.s(28)
      implicitHeight: root.s(28)

      Image {
        id: icon
        anchors.centerIn: parent
        width: root.s(18)
        height: root.s(18)
        source: Quickshell.iconPath(appItem.app.icon)
        fillMode: Image.PreserveAspectFit
      }

      Text {
        anchors.centerIn: parent
        visible: icon.status !== Image.Ready
        text: String.fromCodePoint(0xf02c7) // md-application-outline
        color: Theme.textMuted
        font.family: Theme.glyphFamily
        font.pixelSize: root.s(17)
      }

      HoverHandler { id: hover }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: appLauncher.running = true
      }

      Process {
        id: appLauncher
        command: [Quickshell.env("HOME") + "/.config/hypr/scripts/app-widget",
                  appItem.app.desktopId, appItem.app.wmClass]
      }

      PopupWindow {
        visible: hover.hovered
        anchor.item: appItem
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: root.s(6)
        implicitWidth: nameLabel.implicitWidth + root.s(16)
        implicitHeight: nameLabel.implicitHeight + root.s(8)

        Rectangle {
          anchors.fill: parent
          radius: Theme.radiusCell
          color: Theme.bg
          border.width: Theme.borderWidth
          border.color: Theme.surface
        }

        Text {
          id: nameLabel
          anchors.centerIn: parent
          text: appItem.app.name
          color: Theme.text
          font.family: Theme.uiFamily
          font.pixelSize: root.s(12)
        }
      }
    }
  }
}
