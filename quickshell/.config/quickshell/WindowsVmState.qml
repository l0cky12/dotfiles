pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
  id: root

  readonly property string executable: Quickshell.env("HOME") + "/.local/bin/windows-vm"
  property string phase: "off"

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  Process {
    id: statusProc
    command: [root.executable, "status", "--bar"]
    stdout: StdioCollector {
      onTextChanged: {
        const value = text.trim()
        root.phase = value === "ready" || value === "starting" ? value : "off"
      }
    }
    stderr: StdioCollector {}
    onExited: (code, status) => {
      if (code !== 0) root.phase = "off"
    }
  }

  // Fast only while the VM is up or booting. When off, `windows-vm` pokes
  // the "windows-vm" IPC target (Bar.qml) on start and stop, so the slow poll
  // only catches a VM started some other way.
  Timer {
    interval: root.phase === "off" ? 30000 : 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
