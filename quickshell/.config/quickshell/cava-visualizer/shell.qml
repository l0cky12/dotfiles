//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Standalone cava visualizer: a transparent background-layer panel per
// monitor drawing 64 bottom-up audio bars. This is a separate named
// Quickshell config (launch with `quickshell -c cava-visualizer` or
// `qs -c cava-visualizer`) so it never interferes with the bare shell.qml
// bar instance. It ships its own cava config (cava.conf in this folder)
// and does not touch ~/.config/cava/config or cava/bar.conf.

ShellRoot {
    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: panel

                required property var modelData
                readonly property int barCount: 64
                // Levels normalised to 0..1, one entry per bar.
                property var levels: {
                    const out = []
                    for (let i = 0; i < barCount; i++)
                        out.push(0)
                    return out
                }
                // True once cava has produced at least one valid frame.
                // When false (cava missing or not yet producing frames)
                // only the baseline line is drawn.
                property bool available: false
                // Accent follows the desktop theme (same source the main
                // shell's Theme singleton reads), with the repo's fallback.
                property string accentHex: "#8a6fae"
                // Opt-in: sample the current wallpaper's dominant colour
                // and use it as the bar accent when it survives the
                // brightness thresholds.
                property bool wallpaperAccent: false
                property string wallpaperHex: ""
                // Last wallpaper handed to the sampler. Assigned in
                // sampleWallpaper(); without the declaration that write threw
                // and the opt-in wallpaper accent never ran.
                property string lastSampledPath: ""
                readonly property color accentColor:
                    (wallpaperAccent && wallpaperHex !== "") ? wallpaperHex : accentHex
                // Current-wallpaper path, read from the same state file
                // the wallpaper picker writes. Resolution mirrors the
                // picker: $HYPR_WALLPAPER_STATE_FILE, then $XDG_STATE_HOME,
                // then $HOME/.local/state. Empty while the feature is
                // disabled so the FileView neither watches nor reads
                // anything (FileView autoloads whenever path is set).
                readonly property string wallpaperStatePath: {
                    if (!wallpaperAccent)
                        return ""
                    // Quickshell.env() yields undefined for unset vars, so
                    // guard with truthiness, not !== "".
                    const override = Quickshell.env("HYPR_WALLPAPER_STATE_FILE")
                    if (override)
                        return override
                    const stateHome = Quickshell.env("XDG_STATE_HOME") ||
                        (Quickshell.env("HOME") + "/.local/state")
                    return stateHome + "/hyprland-desktop/wallpaper/current"
                }
                readonly property real accentOpacity: 0.78
                // Throttle repaints to ~30fps to match the cava framerate.
                readonly property int frameIntervalMs: 33
                property bool paintPending: false
                property real idleFadeOpacity: 0.15
                // Idle timeout in minutes. cava.conf sets the same value via
                // its sleep_timer: after that much silence cava stops the
                // FFT and pauses frame output, and the idleWatch timer below
                // marks the panel idle once frames stop arriving. Any new
                // frame (cava wakes on audio input) wakes the panel.
                property int idleTimeoutMinutes: 3
                // Grace beyond cava's own sleep so the frame gap is real.
                readonly property int idleGraceMs: 5000
                // Cava prints a near-zero FFT noise floor on silence, so
                // only sustained above-threshold audio counts as audio.
                readonly property real audioThreshold: 0.02
                readonly property int audioSustainFrames: 4
                property bool idle: false
                property int silenceMs: 0
                property int audioFrames: 0
                property real lastFrameMs: 0
                // Set once cava has produced frames; guards crash respawn.
                property bool everAvailable: false
                // Respawn backoff: attempts reset on any successful frame.
                property int respawnAttempts: 0
                readonly property int respawnMaxAttempts: 5

                onIdleChanged: canvas.requestPaint()
                onAvailableChanged: canvas.requestPaint()
                onAccentColorChanged: canvas.requestPaint()

                screen: modelData

                WlrLayershell.layer: WlrLayer.Background
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                anchors {
                    bottom: true
                    left: true
                    right: true
                }
                exclusiveZone: -1
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                implicitHeight: 120

                // Follow the desktop theme: read the semantic `accent` role
                // from the same theme.json the main shell's Theme singleton
                // watches, so `theme set <slug>` recolours the bars live.
                FileView {
                    id: themeView

                    path: Quickshell.env("HOME") + "/.config/hypr/themes/.active/theme.json"
                    watchChanges: true
                    printErrors: false

                    onFileChanged: reload()
                    onLoaded: {
                        try {
                            const data = JSON.parse(themeView.text()) || ({})
                            if (typeof data.accent === "string")
                                panel.accentHex = data.accent
                        } catch (e) {
                            // Keep the fallback colour on malformed JSON.
                        }
                    }
                    // Missing theme file: keep the fallback colour.
                    onLoadFailed: {}
                }

                FileView {
                    id: wallpaperStateView

                    // Bound to "" while the feature is disabled, so the
                    // FileView is inert: no watch, no read, no sampler.
                    path: panel.wallpaperStatePath
                    watchChanges: true
                    printErrors: false

                    onFileChanged: reload()
                    onLoaded: {
                        const wallpaperPath = String(wallpaperStateView.text()).trim()
                        if (wallpaperPath !== "" &&
                            wallpaperPath !== panel.lastSampledPath)
                            panel.sampleWallpaper(wallpaperPath)
                    }
                    onLoadFailed: {}
                }

                Process {
                    id: sampleProc

                    property string targetPath: ""
                    stdout: SplitParser {
                        onRead: line => {
                            const match = /^#[0-9a-f]{6}$/.exec(String(line).trim())
                            if (match)
                                panel.wallpaperHex = match[0]
                        }
                    }
                    stderr: StdioCollector {}
                    // A failed sample (unreadable wallpaper, Pillow
                    // missing, threshold rejection) must not keep the
                    // previous wallpaper's colour: fall back to the
                    // theme accent.
                    onExited: function (code) {
                        sampleProc.targetPath = ""
                        if (code !== 0)
                            panel.wallpaperHex = ""
                    }
                }

                Process {
                    id: cavaProc

                    command: [
                        "cava",
                        "-p",
                        Quickshell.env("HOME") + "/.config/quickshell/cava-visualizer/cava.conf"
                    ]
                    running: true
                    stdout: SplitParser {
                        // One frame per line: 64 space-separated ints 0..100.
                        onRead: line => panel.handleLine(line)
                    }
                    stderr: StdioCollector {}
                    // If cava is missing or dies, `available` stays/becomes
                    // false and only the baseline line is shown. The
                    // respawn timer below restarts it unless we are idle
                    // (cava's own sleep mode).
                    onExited: {
                        panel.available = false
                        // A crash must not masquerade as cava's sleep
                        // mode: drop any latched idle state so respawn
                        // restarts the visualiser fully awake.
                        panel.idle = false
                        panel.audioFrames = 0
                        panel.silenceMs = 0
                        respawnTimer.restart()
                    }
                }

                function handleLine(line) {
                    const parts = String(line).trim().split(/\s+/).filter(p => p !== "")
                    if (parts.length === 0)
                        return
                    const out = []
                    for (let i = 0; i < barCount; i++) {
                        const n = Number(parts[i] || 0)
                        out.push(Math.min(1, Math.max(0, (isFinite(n) ? n : 0) / 100)))
                    }
                    levels = out
                    available = true
                    everAvailable = true
                    respawnAttempts = 0
                    lastFrameMs = Date.now()

                    const audioPresent = out.some(level => level > audioThreshold)
                    if (audioPresent) {
                        silenceMs = 0
                        audioFrames = Math.min(audioSustainFrames, audioFrames + 1)
                    } else {
                        audioFrames = 0
                        silenceMs += frameIntervalMs
                    }

                    if (idle && audioFrames >= audioSustainFrames) {
                        idle = false
                        silenceMs = 0
                    }
                    if (!idle && silenceMs >= idleTimeoutMinutes * 60000)
                        idle = true
                }

                function sampleWallpaper(path) {
                    // Feature is opt-in: never spawn the sampler (and
                    // never override the theme accent) while disabled.
                    if (!wallpaperAccent || sampleProc.targetPath !== "")
                        return
                    lastSampledPath = path
                    sampleProc.targetPath = path
                    sampleProc.command = [
                        Quickshell.env("HOME") +
                            "/.config/quickshell/cava-visualizer/sample-accent.py",
                        "--threshold", "24", path
                    ]
                    sampleProc.running = true
                }

                // First sample / re-arm when the opt-in flips on (startup
                // or live reload); FileView loads once a path is bound.
                onWallpaperStatePathChanged: {
                    if (wallpaperStatePath !== "")
                        wallpaperStateView.reload()
                }

                // Sleep / wake detection: cava.conf's sleep_timer pauses
                // cava's frame output (and FFT) after the same silence
                // duration, so a sustained frame gap means cava is asleep.
                // The frame-rate-based silence counter above handles the
                // in-frame silence path; this handles the stopped-stream
                // path using wall-clock time.
                Timer {
                    id: idleWatch

                    interval: 1000
                    repeat: true
                    running: panel.everAvailable
                    onTriggered: {
                        const now = Date.now()
                        if (panel.lastFrameMs > 0 &&
                            now - panel.lastFrameMs >=
                                panel.idleTimeoutMinutes * 60000 +
                                panel.idleGraceMs) {
                            if (!panel.idle) {
                                panel.idle = true
                                panel.audioFrames = 0
                            }
                        }
                    }
                }

                // Restart cava if it crashes while it should be running.
                // Skipped while idle (cava's own sleep mode) so a clean
                // config sleep isn't mistaken for a crash.
                Timer {
                    id: respawnTimer

                    interval: 5000
                    repeat: false
                    onTriggered: {
                        if (!panel.available && !panel.idle &&
                            panel.everAvailable && cavaProc.running === false) {
                            if (panel.respawnAttempts < panel.respawnMaxAttempts) {
                                panel.respawnAttempts += 1
                                cavaProc.running = true
                            }
                            // Exceeding the cap leaves cava down; it comes
                            // back on the next shell reload or start.
                        }
                    }
                }

                Timer {
                    id: frameTimer

                    interval: panel.frameIntervalMs
                    repeat: true
                    // Stays running while idle: idle only pauses cava's
                    // frame output, and the timer is what paints a waking
                    // frame instantly (the idle fade is on the Canvas).
                    running: panel.available
                    onTriggered: {
                        if (!panel.paintPending) {
                            panel.paintPending = true
                            canvas.requestPaint()
                        }
                    }
                }

                Canvas {
                    id: canvas

                    anchors.fill: parent
                    // Monitor width is read at runtime from the panel size,
                    // which tracks the screen; bars are recomputed per paint.
                    onPaint: {
                        const ctx = getContext("2d")
                        const w = width
                        const h = height
                        ctx.clearRect(0, 0, w, h)

                        // Flat baseline near the bottom; always visible.
                        const baseline = h - 1.5
                        ctx.strokeStyle = Qt.rgba(
                            panel.accentColor.r,
                            panel.accentColor.g,
                            panel.accentColor.b,
                            panel.accentOpacity)
                        ctx.lineWidth = 1
                        ctx.beginPath()
                        ctx.moveTo(0, baseline)
                        ctx.lineTo(w, baseline)
                        ctx.stroke()

                        if (!panel.available) {
                            panel.paintPending = false
                            return
                        }

                        // 64 evenly spaced bars across the full width.
                        const n = panel.barCount
                        const slot = w / n
                        const barWidth = Math.max(1, slot * 0.7)
                        const maxBarHeight = h - 4
                        ctx.fillStyle = Qt.rgba(
                            panel.accentColor.r,
                            panel.accentColor.g,
                            panel.accentColor.b,
                            panel.accentOpacity)
                        for (let i = 0; i < n; i++) {
                            const level = panel.levels[i] || 0
                            if (level <= 0)
                                continue
                            const barHeight = Math.max(1, level * maxBarHeight)
                            const x = i * slot + (slot - barWidth) / 2
                            // Bottom-up from the baseline.
                            ctx.fillRect(x, baseline - barHeight, barWidth, barHeight)
                        }
                        panel.paintPending = false
                    }
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    opacity: panel.idle ? panel.idleFadeOpacity : 1.0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 400
                        }
                    }
                }
            }
        }
    }
}
