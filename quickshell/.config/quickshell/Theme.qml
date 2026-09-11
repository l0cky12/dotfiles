pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Central palette, typography and metrics for the whole shell.
//
// The palette follows the desktop theme rather than being hardcoded: the theme
// generator (`theme set <slug>`) writes the active theme's semantic palette to
// themes/.active/theme.json, which is watched here, so switching the theme
// recolours the bar and its panels live. The hex literals below survive as
// fallbacks for when that file cannot be read; they are the colours the shell
// used before it was themed.
//
// `fs()` is the "Text Size" knob exposed by DisplayPanel: every font size and
// text-dependent dimension goes through it so that changing the scale rescales
// the bar and its panels as a whole.
Singleton {
  id: root

  // --- semantic palette --------------------------------------------------------
  // These are the roles the theme system defines, in the same vocabulary Rofi,
  // Kitty and Hyprland receive. New shell code should use these names.
  //
  // Surfaces, deepest to nearest. Cards should step up one level, not pick an
  // arbitrary shade: background -> surface -> surfaceAlt.
  readonly property color background: col("background", "#2b2430")
  readonly property color backgroundAlt: col("backgroundAlt", "#1c1720")
  readonly property color surfaceColor: col("surface", "#3a3240")
  readonly property color surfaceAlt: col("surfaceAlt", "#4a4150")
  readonly property color overlay: col("overlay", "#5b5560")

  // Text, brightest to faintest.
  readonly property color foregroundBright: col("foregroundBright", "#e7e2eb")
  readonly property color foreground: col("foreground", "#d7d2db")
  readonly property color muted: col("muted", "#a89fb0")
  readonly property color disabled: col("disabled", "#7d7686")

  readonly property color accent: col("accent", "#8a6fae")
  readonly property color accentAlt: col("accentAlt", "#a98fce")
  // Whatever reads on top of an accent-filled shape. Picked by contrast in the
  // generator, so it is dark on the light themes instead of a hardcoded white.
  readonly property color onAccent: col("onAccent", "#1c1720")

  readonly property color red: col("red", "#e08a8a")
  readonly property color green: col("green", "#8ac08a")
  readonly property color yellow: col("yellow", "#e0c48a")
  readonly property color blue: col("blue", "#8aa2e0")
  readonly property color magenta: col("magenta", "#c48ae0")
  readonly property color cyan: col("cyan", "#8ad0e0")

  // Status roles. Separate from the raw hues so a theme can move "warning" onto
  // its own orange without repainting everything that is literally yellow.
  readonly property color success: col("success", "#8ac08a")
  readonly property color warning: col("warning", "#e0c48a")
  readonly property color critical: col("critical", "#e08a8a")
  readonly property color info: col("info", "#8ad0e0")

  readonly property color selection: col("selection", "#4a4150")
  readonly property color borderColor: col("border", "#3a3240")
  readonly property color borderAccent: col("borderActive", "#8a6fae")
  readonly property color urgent: col("urgent", "#e08a8a")
  readonly property color shadowColor: col("shadow", "#000000")

  // --- structural tokens -------------------------------------------------------
  // Corner treatment, border weight and transparency are part of a theme's
  // personality, so they travel with the palette rather than being fixed here.
  readonly property int hyprRounding: num("rounding", 4)
  readonly property int borderWidth: num("borderWidth", 1)
  readonly property real surfaceOpacity: num("surfaceOpacity", 0.92)
  readonly property real scrimOpacity: num("scrimOpacity", 0.50)
  readonly property real shadowOpacity: num("shadowOpacity", 0.40)

  readonly property string mode: {
    const m = (root.themeData["theme"] || ({}))["mode"]
    return m === "light" ? "light" : "dark"
  }
  readonly property bool isDark: root.mode === "dark"

  // Identity of the active theme, for UI that names it rather than uses it.
  readonly property var themeMeta: root.themeData["theme"] || ({})
  readonly property string themeName: root.themeMeta["name"] || "unknown"
  readonly property string themeSlug: root.themeMeta["slug"] || ""

  // A one-pixel separator that has to be visible on both a near-black and a
  // cream background, so it is derived from the theme's own foreground rather
  // than being a hardcoded translucent white.
  readonly property color hairline: Qt.rgba(
    root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

  // Opacity for states rather than colours: an unavailable control keeps its
  // colour and loses presence.
  readonly property real opacityDisabled: 0.35
  readonly property real opacityInactive: 0.55
  readonly property real opacityUnavailable: 0.45

  // --- legacy aliases ----------------------------------------------------------
  // The 50 other QML files were written against these names. They are kept as
  // aliases onto the semantic roles above so the whole shell picked up the theme
  // system without being rewritten, and so the tuned hierarchy is unchanged.
  readonly property color bg: root.background          // bar + panel background
  readonly property color bgDeep: root.backgroundAlt   // deepest bg / text on accent
  readonly property color surface: root.surfaceColor   // rows, dividers, borders
  readonly property color text: root.foregroundBright  // primary text
  readonly property color textDim: root.foreground     // secondary text
  readonly property color textMuted: root.muted        // de-emphasised
  readonly property color textFaint: root.disabled     // out-of-range
  readonly property color error: root.red              // error text

  // Hyprland draws its active border as a two-stop gradient; matching both
  // stops lets shell chrome sit flush against the compositor's own borders.
  readonly property color borderActive1: root.borderAccent
  readonly property color borderActive2: root.accentAlt

  // Notification chrome is generated for every theme from the same semantic
  // palette. It remains a separate block so notification-specific mappings can
  // evolve without teaching cards about palette names or literal colours.
  readonly property var notificationTheme: root.themeData["notifications"] || ({})
  function notificationCol(key, fallback) {
    const value = root.notificationTheme[key]
    return (typeof value === "string" && value.length > 0) ? value : fallback
  }
  function notificationNum(key, fallback) {
    const value = root.notificationTheme[key]
    if (typeof value === "number") return value
    const parsed = parseFloat(value)
    return isNaN(parsed) ? fallback : parsed
  }
  readonly property color notificationBackground: notificationCol("background", root.background)
  readonly property color notificationText: notificationCol("text", root.foregroundBright)
  readonly property color notificationBodyText: notificationCol("bodyText", root.foreground)
  readonly property color notificationBorder1: notificationCol("border1", root.borderActive1)
  readonly property color notificationBorder2: notificationCol("border2", root.borderActive2)
  readonly property real notificationBorderAlpha: notificationNum("borderAlpha", 1.0)
  readonly property real notificationBorderAngle: notificationNum("borderAngle", 45)
  readonly property color notificationCountdown: notificationCol("countdown", root.accent)
  readonly property color notificationClose: notificationCol("close", root.muted)
  readonly property int notificationRadius: fs(Math.max(0, root.hyprRounding))

  // --- theme source -----------------------------------------------------------
  // theme.json is generated by `theme-generate set` and carries the full
  // semantic palette (`colors.*`, `style.*`) as ready-to-use "#RRGGBB" hex.

  readonly property string themeFile: Quickshell.env("HOME") + "/.config/hypr/themes/.active/theme.json"

  property var themeData: ({})          // parsed theme.json
  readonly property var themeColors: root.themeData["colors"] || ({})
  readonly property var themeStyle: root.themeData["style"] || ({})

  // Semantic colour by key, falling back to the shell's original literal.
  function col(key, fallback) {
    const v = root.themeColors[key]
    return (typeof v === "string" && v.length > 0) ? v : fallback
  }

  // Same, for the theme's `style` block.
  function num(key, fallback) {
    const v = root.themeStyle[key]
    return typeof v === "number" ? v : fallback
  }

  // The generator installs theme.json with os.replace(), so the file the
  // watcher holds open is unlinked rather than rewritten and the inotify watch
  // dies with it. watchChanges still covers an in-place edit; `theme set` tells
  // us over IPC instead (see reloadPalette, called from the "theme" handler in
  // Bar.qml), and reload() re-arms the watch on the new inode either way.
  function reloadPalette() {
    themeFileView.reload()
  }

  FileView {
    id: themeFileView
    path: root.themeFile
    watchChanges: true
    printErrors: false

    onFileChanged: reload()
    onLoaded: {
      try {
        root.themeData = JSON.parse(themeFileView.text()) || ({})
      } catch (e) {
        console.warn("Theme: theme.json is not valid JSON:", e)
        root.themeData = ({})
      }
    }
    // Leave themeData empty so every colour falls back to its literal.
    onLoadFailed: root.themeData = ({})
  }

  // --- typography ---
  readonly property string glyphFamily: "JetBrainsMono Nerd Font"
  readonly property string uiFamily: "sans-serif"

  // --- radii ---
  // Scaled with the text so that pill shapes stay pills as rows grow.
  readonly property int radiusRow: fs(4)
  readonly property int radiusCell: fs(5)
  readonly property int radiusTrack: fs(10)

  // --- scaling ---
  // Persisted to disk; also mirrored to GTK apps via gsettings.
  property alias fontScale: stateData.fontScale

  readonly property var textScalePresets: [0.9, 1.0, 1.1, 1.25, 1.5]

  // Scale a design-time pixel value. Reads `fontScale`, so bindings that call
  // this re-evaluate when the scale changes.
  function fs(n) {
    return Math.round(n * root.fontScale)
  }

  // --- drawer / card tokens ---------------------------------------------------
  // Caelestia-style proportions for the dashboard drawer. Everything goes through
  // fs() so the Text Size control still scales the whole drawer.
  readonly property int gapXS: fs(4)
  readonly property int gapS: fs(8)
  readonly property int gapM: fs(12)
  readonly property int gapL: fs(16)
  readonly property int gapXL: fs(24)

  readonly property int radiusS: fs(12)
  readonly property int radiusM: fs(16)
  readonly property int radiusL: fs(20)
  readonly property int radiusXL: fs(26)

  readonly property int drawerPadding: fs(16)
  readonly property int navHeight: fs(60)
  readonly property int navIcon: fs(21)
  readonly property int navLabel: fs(13)
  readonly property int tabIndicator: fs(3)
  readonly property int tabIndicatorGap: fs(5)

  // Page intrinsic sizes. These are what the drawer animates between.
  readonly property int dashPageW: fs(720)
  // Tall enough for the full 6-week calendar grid (~250px) plus both rows.
  readonly property int dashPageH: fs(770)   // + the web apps launcher tile
  readonly property int mediaPageW: fs(900)
  readonly property int mediaPageH: fs(480)
  readonly property int perfPageW: fs(860)
  readonly property int perfPageH: fs(352)
  readonly property int weatherPageW: fs(840)
  // header(180) + gap + hourly(170) + gap + forecast(250)
  readonly property int weatherPageH: fs(624)
  readonly property int weatherHeaderH: fs(180)
  readonly property int hourlyCardH: fs(170)
  // 7 rows of 24 + 4 spacing, plus card title and padding.
  readonly property int forecastCardH: fs(250)

  // Card sizes
  readonly property int weatherCardW: fs(250)
  readonly property int weatherCardH: fs(170)
  readonly property int profileCardW: fs(300)
  readonly property int dateCardW: fs(120)
  readonly property int dateCardH: fs(200)
  // 6-week grid (~240) + card title (~22) + padding (32).
  readonly property int calendarCardH: fs(300)
  readonly property int mediaPreviewW: fs(230)
  readonly property int coverSize: fs(280)
  readonly property int mediaSideW: fs(290)
  readonly property int lyricsW: fs(290)
  readonly property int heroCardW: fs(260)
  readonly property int heroCardH: fs(210)
  readonly property int heroGauge: fs(92)
  // Five of these plus four gaps must fit perfPageW: 5*162 + 4*12 = 858.
  readonly property int smallCardW: fs(162)
  readonly property int smallCardH: fs(130)
  readonly property int hourCardW: fs(85)
  readonly property int hourCardH: fs(120)
  readonly property int avatarSize: fs(66)

  // --- keybindings menu tokens ------------------------------------------------
  // Every dimension and colour weight of the Super+K palette lives here; nothing
  // in KeybindsPanel.qml is hardcoded, so the whole look is tuned from this block.
  readonly property int menuWidth: fs(800)
  readonly property int menuMaxHeight: fs(500)
  readonly property int menuHeaderHeight: fs(34)
  readonly property int menuRowHeight: fs(50)
  readonly property int menuPadding: fs(24)      // generous side padding, as in the reference
  readonly property int menuFontBody: fs(12)
  readonly property int menuFontTitle: fs(14)
  readonly property int menuBorderWidth: fs(Math.max(1, root.borderWidth))
  readonly property int menuRadius: fs(6)        // near-square, matching Hyprland's rounding
  readonly property int menuOuterMargin: fs(40)  // smallest gap to the screen edge
  // Shortcut column is measured from the longest visible shortcut, then clamped
  // here so the arrow never drifts between rows.
  readonly property int menuColumnMin: fs(160)
  readonly property int menuColumnMax: fs(260)
  // The scrim follows the theme: a translucent theme like Ethereal dims gently,
  // a solid one like Lumon or Vantablack dims hard.
  readonly property real menuScrimOpacity: root.scrimOpacity
  readonly property real menuSelectedAlpha: 0.08 // selected row bg: foreground @ 8%
  readonly property real menuBorderAlpha: 0.25   // selected row border

  // --- theme picker (cover-flow carousel) -------------------------------------
  // Design-space geometry for the Super+Ctrl+Shift+Space carousel, in the units
  // the layout was designed at. These deliberately do NOT go through fs():
  // the carousel scales from monitor geometry (see ThemePicker.scale) rather
  // than from the Text Size setting, because a preview is a picture of a
  // desktop -- growing it with the UI font would overflow the portrait monitor.
  //
  // The picker's chrome uses the semantic colour roles above, i.e. the theme
  // that is currently applied. Each preview paints itself from its own palette
  // out of the index model. That split is what keeps the picker Everforest-
  // coloured while you are browsing Tokyo Night.
  readonly property real coverSelectedW: 768
  readonly property real coverSelectedH: 475      // aspect 1.617
  readonly property real coverSliceW: 108
  readonly property real coverSliceH: 432
  readonly property real coverSliceSpacing: -30   // negative: slices overlap
  readonly property real coverItemStep: root.coverSliceW + root.coverSliceSpacing  // 78
  readonly property real coverSkew: 28            // outer-edge pull-in per corner
  readonly property real coverSelectedBorder: 3
  readonly property real coverSliceBorder: 1
  readonly property real coverSideDim: 0.42       // unselected dim, over theme bg
  readonly property real coverTopMargin: 30
  readonly property real coverLabelGap: 16
  readonly property real coverLabelFont: 26       // theme name under the carousel
  readonly property real coverFilterFont: 15      // filter echo, only while typing
  readonly property real coverLabelH: 34
  readonly property real coverFilterH: 26
  // How many slices are built each side. Beyond this nothing is instantiated,
  // which is also what bounds how many wallpapers can be in flight.
  readonly property int coverVisibleRadius: 7
  // How far out a wallpaper Image is allowed a source at all.
  readonly property int coverLoadRadius: 8
  readonly property real coverScrimOpacity: Math.min(0.94, root.scrimOpacity + 0.34)

  // --- web app manager tokens -------------------------------------------------
  // The Super+Shift+A overlay. Sized in scaled units like the rest of the shell
  // (unlike the theme carousel, which is a picture of a desktop and scales from
  // the monitor instead).
  readonly property int webappCardW: fs(560)
  readonly property int webappCardH: fs(520)
  readonly property int webappOuterMargin: fs(48)
  readonly property int webappPadding: fs(22)
  readonly property int webappFieldH: fs(34)
  readonly property int webappRowH: fs(52)
  readonly property int webappIconPlate: fs(44)
  readonly property int webappPreview: fs(64)
  readonly property int webappFontTitle: fs(15)
  readonly property int webappFontBody: fs(12)
  readonly property int webappFontSmall: fs(10)
  readonly property int webappButtonH: fs(30)
  readonly property real webappScrimOpacity: Math.min(0.92, root.scrimOpacity + 0.3)

  // Shared easing for drawer resize and indicator movement.
  readonly property int animFast: 130

  // Metrics that must track the font scale so text does not clip.
  // 45px bar = ~33px inner widget area + ~6px padding above and below.
  readonly property int barHeight: fs(45)
  readonly property int barInner: fs(33)
  readonly property int panelMargin: fs(16)
  readonly property int sectionSpacing: fs(14)
  readonly property int itemSpacing: fs(8)

  // --- persistence ---
  FileView {
    id: stateFile
    path: Quickshell.statePath("shell-state.json")
    watchChanges: true
    printErrors: false

    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()

    // First run: no file yet, so create it from the defaults.
    onLoadFailed: function (error) {
      if (error === FileViewError.FileNotFound)
        stateFile.writeAdapter()
    }

    JsonAdapter {
      id: stateData
      property real fontScale: 1.0
    }
  }

  // Mirror the shell font scale onto GTK apps. Fires on startup too, so the
  // persisted value is re-asserted after a reboot; the JSON file is the source
  // of truth, not the current gsettings value.
  onFontScaleChanged: root.applyGtkTextScale()

  function applyGtkTextScale() {
    const s = Number(root.fontScale)
    if (!isFinite(s) || s <= 0)
      return
    gtkScaleProc.command = ["gsettings", "set",
                            "org.gnome.desktop.interface",
                            "text-scaling-factor", s.toFixed(2)]
    gtkScaleProc.running = true
  }

  Process {
    id: gtkScaleProc
    stdout: StdioCollector {}
    stderr: StdioCollector { id: gtkScaleErr }
    onExited: function (code) {
      if (code !== 0)
        console.warn("Theme: gsettings text-scaling-factor failed:",
                     gtkScaleErr.text.trim())
    }
  }
}
