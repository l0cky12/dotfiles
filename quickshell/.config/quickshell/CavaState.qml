pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Audio spectrum state for the bar visualiser, driven by cava.
//
// cava is launched with the shipped config (cava/bar.conf) so it emits one
// ASCII frame per line: 25 space-separated integers in 0..100, one per
// bar. Each frame is normalised into `levels` (0..1). `available` is true
// only once a valid frame has been parsed, so MediaIcon can fall back to
// its built-in animation whenever cava is missing or failing.
Singleton {
  id: root

  // Must match cava/bar.conf. MediaIcon keeps using the first four bands.
  readonly property int barCount: 25
  // Levels normalised to 0..1, one entry per bar.
  property var levels: Array(root.barCount).fill(0)
  // True once cava has produced at least one valid frame.
  property bool available: false

  // "12 45 78 99" -> [0.12, 0.45, 0.78, 0.99], padded/clamped to barCount.
  function parseFrame(line) {
    const parts = String(line).trim().split(/\s+/).filter(p => p !== "")
    if (parts.length === 0)
      return null
    const max = 100
    const out = []
    for (let i = 0; i < root.barCount; i++) {
      const n = Number(parts[i] || 0)
      out.push(Math.min(1, Math.max(0, (isFinite(n) ? n : 0) / max)))
    }
    return out
  }

  function handleLine(line) {
    const frame = parseFrame(line)
    if (frame === null)
      return
    root.levels = frame
    root.available = true
  }

  Process {
    id: cavaProc
    // Runs only while audio is playing, so the FFT cost is paid just when
    // the visualiser is moving. The `running` binding restarts cava each
    // time playback resumes; if cava dies mid-playback the bar stays on
    // the fallback animation until playback next toggles or the shell
    // reloads (accepted limitation).
    // The always-visible MediaIcon also consumes the spectrum with panels closed.
    running: MediaState.isPlaying
    command: ["cava", "-p", Quickshell.env("HOME") + "/.config/quickshell/cava/bar.conf"]
    stdout: SplitParser {
      onRead: line => root.handleLine(line)
    }
    stderr: StdioCollector {}
    // Any exit (cava missing, bad audio source, clean stop) drops the bar
    // back to the fallback animation until the next start.
    onExited: function(code) {
      root.available = false
    }
  }
}
