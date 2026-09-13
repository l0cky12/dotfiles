pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// State for the web app manager overlay (Super+Alt+A), and for the one-step
// install of the focused browser page (Super+Space).
//
// This is a front-end only. Every filesystem and network operation lives in the
// `webapp` backend; the shell just collects a name and a URL, shows what the
// backend reports, and asks it to install or remove. Nothing here builds a shell
// command string -- each Process takes an argument array, so a name or URL can
// never be reinterpreted as syntax.
//
//   webapp list --json          -> apps[]        (the model)
//   webapp discover-icon <url>  -> icon preview   (async, never blocks the UI)
//   webapp install ...          -> creates metadata + icon + .desktop
//   webapp remove <id>          -> removes exactly those three
Singleton {
  id: root

  // --- panel lifecycle --------------------------------------------------------

  property bool panelVisible: false
  property string panelScreen: ""

  // The view the panel should land on the next time it opens. WebAppPanel reads
  // and clears it; "install" is only ever set by installCurrent().
  property string requestedMode: "list"

  function togglePanel(screenName) {
    if (panelVisible && panelScreen === screenName) {
      panelVisible = false
      return
    }
    if (screenName === "")
      return
    panelScreen = screenName
    panelVisible = true
    root.refresh()
  }

  function close() {
    root.panelVisible = false
  }

  // --- backend ----------------------------------------------------------------
  // Invoked by path rather than relying on `webapp` being on PATH: the shell is
  // started by Hyprland, whose environment does not include ~/.local/bin.

  readonly property string manager:
    Quickshell.env("HOME") + "/.config/hypr/webapp/manager.py"

  // --- model ------------------------------------------------------------------

  property var apps: []
  property var loadErrors: []
  property string lastError: ""
  property bool loading: false

  function refresh() {
    root.loading = true
    listProc.running = true
  }

  Process {
    id: listProc
    command: ["python3", root.manager, "list", "--json"]

    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "")
          return
        try {
          const data = JSON.parse(text)
          root.apps = data["apps"] || []
          root.loadErrors = data["errors"] || []
          root.lastError = ""
        } catch (e) {
          root.lastError = "Could not read the web app list: " + e
        }
      }
    }
    stderr: StdioCollector { id: listErr }

    onExited: function (code) {
      root.loading = false
      if (code !== 0 && root.apps.length === 0)
        root.lastError = listErr.text.trim() || "webapp list failed"
    }
  }

  // --- install form -----------------------------------------------------------
  // Kept on the singleton so a half-filled form survives closing the overlay.

  property string formName: ""
  property string formUrl: ""
  property string iconPath: ""      // staged icon the backend found or the user picked
  property string iconState: ""     // "", "searching", "found", "none", "chosen"
  property bool installing: false
  property string formError: ""

  function resetForm() {
    root.formName = ""
    root.formUrl = ""
    root.iconPath = ""
    root.iconState = ""
    root.formError = ""
  }

  // Mirrors the backend's rules closely enough to gate the Install button
  // without a round-trip on every keystroke. The backend re-validates
  // authoritatively -- this only decides whether the button is live.
  readonly property bool nameValid: root.formName.trim().length > 0
                                 && root.formName.trim().length <= 96
  readonly property bool urlValid: {
    const u = root.formUrl.trim()
    if (u.length === 0)
      return false
    if (/\s/.test(u))
      return false
    // A scheme other than http(s) is invalid; no scheme at all is fine and gets
    // promoted to https by the backend.
    const m = /^([a-zA-Z][a-zA-Z0-9+.\-]*):/.exec(u)
    if (m && m[1].toLowerCase() !== "http" && m[1].toLowerCase() !== "https") {
      // "localhost:8080/app" is a host:port, not a scheme.
      const rest = u.slice(m[0].length)
      if (!/^\d+(\/|$)/.test(rest))
        return false
    }
    const host = u.replace(/^[a-zA-Z][a-zA-Z0-9+.\-]*:\/\//, "").split(/[\/?#]/)[0]
    return host.indexOf(".") !== -1 || host.split(":")[0] === "localhost"
  }
  readonly property bool canInstall: root.nameValid && root.urlValid
                                  && !root.installing

  // Icon discovery is debounced so typing a URL does not fire a request per
  // keystroke, and runs in its own process so the shell never waits on the
  // network.
  Timer {
    id: iconDebounce
    interval: 700
    onTriggered: root.discoverIcon()
  }

  function urlEdited(text) {
    // The field's text is bound to formUrl, so setting formUrl from code (see
    // prefillUrl) echoes straight back here. Ignoring the echo keeps that path
    // to a single icon lookup instead of two.
    if (text === root.formUrl)
      return
    root.formUrl = text
    root.formError = ""
    if (root.iconState !== "chosen") {
      root.iconPath = ""
      root.iconState = ""
      if (root.urlValid)
        iconDebounce.restart()
      else
        iconDebounce.stop()
    }
  }

  function discoverIcon() {
    if (!root.urlValid)
      return
    root.iconState = "searching"
    iconProc.command = ["python3", root.manager, "discover-icon", root.formUrl.trim()]
    iconProc.running = true
  }

  Process {
    id: iconProc
    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "")
          return
        try {
          const d = JSON.parse(text)
          if (d.ok) {
            root.iconPath = d.path
            root.iconState = "found"
          } else {
            root.iconPath = ""
            root.iconState = "none"
          }
          // The suggestion is derived from the host, so it is worth having even
          // when no icon was found -- that is the case a Super+Space install
          // lands in when the site has no usable icon. Only ever fills an empty
          // field; never overwrites what was typed.
          if (root.formName.trim() === "" && d.suggested_name)
            root.formName = d.suggested_name
        } catch (e) {
          root.iconState = "none"
        }
      }
    }
    stderr: StdioCollector {}
    onExited: function (code) {
      if (code !== 0 && root.iconState === "searching")
        root.iconState = "none"
    }
  }

  // --- install the focused page (Super+Space) ---------------------------------
  //
  // ~/.local/bin/webapp-current works out the URL of the focused browser window
  // from its Wayland class, writes it to $XDG_RUNTIME_DIR/webapp-current-url
  // (0600), and then calls `quickshell ipc call webapps installCurrent`. That
  // file is the whole handoff contract; the script's header documents the same
  // thing from its side.
  //
  // A file rather than an IPC argument because no target in this shell takes
  // one, and it keeps a URL reconstructed from a window class out of an
  // argument list. The script rewrites the file on every run -- writing an
  // empty line when it could not recover a URL -- so this is never stale.
  // An empty file simply opens the form empty, which is the right answer for a
  // plain browser tab: the class of a normal window carries no URL.

  readonly property string handoffPath:
    (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/webapp-current-url"

  // Raised when the form is opened this way, for a panel that is already on
  // screen; requestedMode covers the panel that is about to open. Both run and
  // both land on "install", so the order they arrive in does not matter.
  signal showInstallForm()

  // The panel opens first and the URL lands in it afterwards. Reading the file
  // is asynchronous, and the form is worth having either way: a missing or
  // unreadable handoff file leaves an empty form, which is what a plain browser
  // tab gets anyway.
  function installCurrent(screenName) {
    if (screenName === "")
      return
    root.resetForm()
    root.requestedMode = "install"
    root.panelScreen = screenName
    root.panelVisible = true
    root.refresh()
    root.showInstallForm()
    handoffFile.reload()
  }

  FileView {
    id: handoffFile
    path: root.handoffPath
    printErrors: false

    // There is deliberately no onLoadFailed: a missing or unreadable file is
    // the ordinary state before the first Super+Space, and the form is already
    // open and already empty by the time this resolves either way.
    onLoaded: root.prefillUrl(handoffFile.text())
  }

  // Prefills the URL field without the typing debounce: the address is known in
  // full, so there is nothing to wait for. The name is deliberately left empty
  // -- discover-icon reports the backend's own host-derived suggestion and
  // iconProc fills it in, so that rule stays in one place.
  function prefillUrl(url) {
    const clean = String(url || "").trim()
    root.formUrl = clean
    root.formError = ""
    root.iconPath = ""
    root.iconState = ""
    iconDebounce.stop()
    if (root.urlValid)
      root.discoverIcon()
  }

  function chooseIcon(path) {
    if (!path)
      return
    root.iconPath = path
    root.iconState = "chosen"
  }

  // --- install ----------------------------------------------------------------

  function install() {
    if (!root.canInstall)
      return
    root.installing = true
    root.formError = ""
    // An argument array: the name and URL are separate argv entries, so quoting
    // and metacharacters are a non-issue.
    const cmd = ["python3", root.manager, "install",
                 "--name", root.formName.trim(),
                 "--url", root.formUrl.trim(), "--json"]
    if (root.iconPath !== "")
      cmd.push("--icon", root.iconPath)
    installProc.command = cmd
    installProc.running = true
  }

  signal installed(string name)

  Process {
    id: installProc
    stdout: StdioCollector { id: installOut }
    stderr: StdioCollector { id: installErr }
    onExited: function (code) {
      root.installing = false
      if (code !== 0) {
        // Surfaced in the form, not swallowed: the backend's message is the
        // actionable part (duplicate id, bad URL, unwritable directory).
        root.formError = installErr.text.trim() || "install failed"
        console.warn("WebAppState: install failed:", root.formError)
        return
      }
      const name = root.formName.trim()
      root.resetForm()
      root.refresh()
      root.installed(name)
    }
  }

  // --- remove -----------------------------------------------------------------
  // Two-step: the row asks first. The shell has no confirmation dialog anywhere,
  // so this is an in-row confirm rather than a modal.

  property string confirmingId: ""

  function askRemove(id) { root.confirmingId = id }
  function cancelRemove() { root.confirmingId = "" }

  function remove(id) {
    if (!id)
      return
    root.confirmingId = ""
    removeProc.command = ["python3", root.manager, "remove", id, "--json"]
    removeProc.running = true
  }

  Process {
    id: removeProc
    stdout: StdioCollector {}
    stderr: StdioCollector { id: removeErr }
    onExited: function (code) {
      if (code !== 0)
        root.lastError = removeErr.text.trim() || "remove failed"
      else
        root.lastError = ""
      root.refresh()
    }
  }

  // Choosing an icon by hand.
  //
  // There is deliberately no native file dialog: Quickshell provides none, and
  // this desktop has no zenity/kdialog/yad to borrow one from. Rather than pull
  // in a dependency for a rarely-used path, an icon can be supplied two ways
  // that need nothing extra -- drag an image file onto the preview, or type a
  // path. The backend sniffs the file's magic bytes either way, so a wrong file
  // is rejected with a clear message rather than producing a broken launcher.
  property bool iconPathFieldVisible: false

  function setIconPath(path) {
    let p = (path || "").trim()
    if (p === "")
      return
    // A drop arrives as a file:// URL; the backend wants a plain path.
    if (p.indexOf("file://") === 0)
      p = decodeURIComponent(p.substring(7))
    root.chooseIcon(p)
  }

  function clearChosenIcon() {
    root.iconPath = ""
    root.iconState = ""
    if (root.urlValid)
      root.discoverIcon()
  }

  // Nerd Font glyphs; codepoints above U+FFFF need fromCodePoint, not \u.
  readonly property string glyphWeb: String.fromCodePoint(0xf0ac7)
  readonly property string glyphAdd: String.fromCodePoint(0xf0415)
  readonly property string glyphDelete: String.fromCodePoint(0xf01b4)
  readonly property string glyphBack: String.fromCodePoint(0xf004d)
}
