import Quickshell
import QtQuick

// Offscreen parse/instantiation harness for the configured app launcher.
Scope {
  id: smoke
  AppLauncher { id: launcher }

  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (launcher.apps.length === 0)
        return
      const app = launcher.apps[0]
      if (app.desktopId === "spotify" && app.name === "Spotify"
          && app.icon === "spotify-client" && app.wmClass === "spotify")
        console.log("ok: App launcher configuration")
      else
        console.log("FAIL: App launcher configuration")
      Qt.quit()
    }
  }

  Timer {
    interval: 1000
    running: true
    onTriggered: {
      console.log("FAIL: App launcher smoke test timed out")
      Qt.quit()
    }
  }
}
