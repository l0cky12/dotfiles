import QtQuick
import Quickshell

// Headless render of the bar's island chrome. Bar.qml itself cannot be loaded
// in a fixture -- its IpcHandlers would collide with the running daemon's --
// so this mounts the same modules inside the same BarIsland capsules over a
// stand-in wallpaper, which is what the real bar draws them on.
FloatingWindow {
  id: window
  implicitWidth: 900
  implicitHeight: Theme.barHeight
  color: "#6a4a7a"

  BarIsland {
    id: leftIsland
    anchors.left: parent.left
    anchors.leftMargin: Theme.barSideMargin
    anchors.verticalCenter: parent.verticalCenter

    WorkspacesModule {}
  }

  Row {
    anchors.right: parent.right
    anchors.rightMargin: Theme.barSideMargin
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.barIslandGap

    BarIsland {
      id: trayIsland
      anchors.verticalCenter: parent.verticalCenter

      AppLauncher {}
      AgentIcon {}
      WindowsVmIcon {}
      BluetoothIcon { screenName: "fixture" }
      NetworkIcon { screenName: "fixture" }
      AudioIcon { screenName: "fixture" }
      BatteryIcon {}
    }

    BarIsland {
      id: powerIsland
      anchors.verticalCenter: parent.verticalCenter
      implicitWidth: Theme.barIslandHeight

      IconButton {
        anchors.verticalCenter: parent.verticalCenter
        bordered: false
        glyph: String.fromCodePoint(0xf0425)
      }
    }
  }

  Component.onCompleted: {
    let failures = 0
    let checks = 0
    function check(label, ok) {
      checks++
      if (!ok) { failures++; console.log("FAIL: " + label) }
    }

    check("island is a stadium, not a slab",
          leftIsland.radius === leftIsland.height / 2)
    check("island height matches the theme metric",
          leftIsland.height === Theme.barIslandHeight)
    check("island is sized to its modules",
          leftIsland.width > Theme.barIslandPadding * 2)
    check("tray island is sized to its modules",
          trayIsland.width > Theme.barIslandPadding * 2)
    check("power island is circular",
          powerIsland.width === powerIsland.height)
    check("reserved strip clears the island on both sides",
          Theme.barHeight === Theme.barIslandHeight + Theme.barGap * 2)

    // A rotated 1920x1080 output gives a 1080px bar, which does not fit three
    // island groups at full scale. The scale curve, not the layout, is what
    // keeps them apart.
    check("a wide bar gets the full content scale",
          Theme.barScaleFor(1920) === 1.25)
    check("a rotated monitor's 1080px bar scales down to fit",
          Theme.barScaleFor(1080) < 1.2 && Theme.barScaleFor(1080) > 1.0)
    check("scale never collapses on a very narrow bar",
          Theme.barScaleFor(300) === 0.85)
    check("scale is monotonic in width",
          Theme.barScaleFor(900) < Theme.barScaleFor(1080))

    console.log("assertions: " + checks)
    if (failures === 0) console.log("omakub bar smoke: ok")
    else console.log("omakub bar smoke: " + failures + " failed")
  }
}
