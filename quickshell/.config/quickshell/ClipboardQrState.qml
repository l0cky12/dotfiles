pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Renders whatever is on the clipboard as a QR code for ClipboardQrOverlay.
//
// The lmenu row this replaced piped wl-paste through qrencode straight back
// onto the clipboard, which put a picture of the clipboard *on* the clipboard:
// nothing left to scan with, and the original content gone. The code now goes
// on screen instead, the same way the Wi-Fi one does.
//
// Deliberately a separate singleton from ClipboardState rather than another
// section of it: that one owns the cliphist history panel, with its own
// screen, selection, poll cycle and error line. Sharing those would make the
// overlay and the history panel fight over one panelScreen/lastError pair for
// two surfaces that never appear together.
//
// Nothing here shows a failure on screen. An overlay whose only content is an
// error is worse than a notification, so a clipboard that cannot be encoded
// notifies and leaves the screen alone -- see qrProc below.
Singleton {
  id: root

  // Screen owning the overlay. Like NetworkState.overlayScreen, this is the
  // screen the request came from rather than a monitor the window picks.
  property string overlayScreen: ""
  property bool loading: false
  // Set only once an SVG exists on disk; the overlay's visibility binds to it,
  // so clearing it is also the dismissal.
  property string resultPath: ""
  property string error: ""

  // XDG_RUNTIME_DIR is per-user and already mode 0700, which matters here: a
  // clipboard often holds a password, and this writes it out as something a
  // camera can read. The file is overwritten in place rather than accumulating
  // one QR per invocation, and the runtime dir is wiped at logout.
  readonly property string outputPath:
    (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/clipboard-qr.svg"

  // One `sh -c` step: take the clipboard as text, refuse an empty one, encode
  // it. Every failure exits nonzero after putting one sentence on stderr, and
  // that sentence is what the notification shows.
  //
  // The output path arrives as $1 instead of being interpolated into the
  // script, so no part of the environment can be read as shell syntax. The
  // scratch file lets qrencode read from a file (-r) rather than a pipe, which
  // keeps "the clipboard was empty" distinguishable from "qrencode refused
  // it" without relying on pipefail.
  //
  // tests/clipboard-qr.test.sh lifts these lines out and runs them against
  // fake wl-paste/qrencode binaries, so keep every element one single-quoted
  // line with no concatenation.
  readonly property string script: [
    'umask 077',
    'rm -f "$1" "$1.txt"',
    'wl-paste --no-newline --type text >"$1.txt" 2>/dev/null || true',
    'if [ ! -s "$1.txt" ]; then rm -f "$1.txt"; echo "There is no text on the clipboard to turn into a QR code." >&2; exit 2; fi',
    'if ! qrencode -t SVG -r "$1.txt" -o "$1"; then rm -f "$1.txt" "$1"; exit 3; fi',
    'rm -f "$1.txt"'
  ].join("; ")

  // Opens the overlay on `screenName` with a freshly generated code. Called
  // from the clipboard-qr IPC handler in Bar.qml.
  function show(screenName) {
    if (loading || screenName === "")
      return
    overlayScreen = screenName
    // Cleared before every run so the overlay cannot show the previous
    // clipboard while this one is still encoding, and so a re-open re-binds
    // the Image source even though the file name never changes.
    resultPath = ""
    error = ""
    loading = true
    qrProc.running = true
  }

  // Clearing resultPath is both the dismissal and the close.
  function close() {
    resultPath = ""
  }

  // qrencode prefixes its own name and may say more than one thing; the
  // notification gets the last, most specific sentence.
  function errorText(text) {
    const lines = String(text || "").split("\n").map(l => l.trim()).filter(l => l !== "")
    return lines.length > 0 ? lines[lines.length - 1] : ""
  }

  Process {
    id: qrProc
    command: ["sh", "-c", root.script, "clipboard-qr", root.outputPath]
    stdout: StdioCollector {}
    stderr: StdioCollector { id: qrErr }
    onExited: function (code) {
      root.loading = false
      if (code === 0) {
        root.error = ""
        root.resultPath = root.outputPath
        return
      }
      // Nothing to scan means nothing to show: notify and leave the screen
      // untouched rather than opening an overlay over an error message.
      root.error = root.errorText(qrErr.text) || "Could not turn the clipboard into a QR code."
      notifyProc.command = ["notify-send", "-a", "Clipboard", "QR code", root.error]
      notifyProc.running = true
    }
  }

  Process {
    id: notifyProc
    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }
}
