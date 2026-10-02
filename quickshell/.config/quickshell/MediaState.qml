pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// Media backend, built on Quickshell's native MPRIS service.
//
// Handles every MPRIS player, not just Spotify: the active player is normally
// the one that most recently started playing, and can be pinned from the panel.
// Capability flags are honoured throughout, because they genuinely differ --
// Spotify supports next/previous/shuffle/loop while Brave reports
// canGoNext == false and exposes neither shuffle nor loop.
//
// Positions and lengths from Quickshell are in SECONDS (it converts the
// microseconds MPRIS reports).
Singleton {
  id: root

  property bool panelVisible: false
  // Connector name of the screen whose bar opened the panel, matching the
  // convention used by NetworkState / AudioState / DisplayState.
  property string panelScreen: ""

  function togglePanel(screenName) {
    if (panelVisible && panelScreen === screenName) {
      panelVisible = false
      return
    }
    if (screenName === "")
      return
    panelScreen = screenName
    panelVisible = true
  }

  // --- players ---------------------------------------------------------------

  readonly property var players: Mpris.players ? Mpris.players.values : []

  // Session-only: a pin that survived a restart would usually point at a player
  // that no longer exists.
  property string pinnedDbusName: ""

  // dbusName -> counter stamped when the player *started* playing (cleared when
  // it stops) and when it was last seen playing (never cleared). Ordering uses a
  // monotonic counter rather than a wall clock.
  property var startStamps: ({})
  property var lastStamps: ({})
  property int stampSeq: 0

  readonly property var active: {
    const list = root.players
    if (list.length === 0)
      return null

    if (root.pinnedDbusName !== "") {
      for (var i = 0; i < list.length; i++)
        if (list[i].dbusName === root.pinnedDbusName)
          return list[i]
    }

    var best = null
    var bestKey = -1
    var bestPlaying = false
    for (var j = 0; j < list.length; j++) {
      const p = list[j]
      const playing = p.playbackState === MprisPlaybackState.Playing
      const key = playing
        ? (root.startStamps[p.dbusName] || 0)
        : (root.lastStamps[p.dbusName] || 0)
      if (best === null
          || (playing && !bestPlaying)
          || (playing === bestPlaying && key > bestKey)) {
        best = p
        bestKey = key
        bestPlaying = playing
      }
    }
    return best
  }

  // Reading playbackState is a cached QML property, not a D-Bus round trip, so
  // this poll is essentially free. It runs unconditionally because a player
  // starting playback is exactly the event we must notice, and the fast position
  // timer below is stopped at that moment.
  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshStamps()
  }

  function refreshStamps() {
    const list = root.players
    // Fresh objects, not in-place mutation: assigning the same reference back
    // would not emit a change notification, so `active` would never re-evaluate.
    const starts = {}
    const lasts = {}
    for (var k in root.startStamps)
      starts[k] = root.startStamps[k]
    for (var k2 in root.lastStamps)
      lasts[k2] = root.lastStamps[k2]
    var changed = false

    for (var i = 0; i < list.length; i++) {
      const p = list[i]
      const name = p.dbusName
      if (p.playbackState === MprisPlaybackState.Playing) {
        if (!starts[name]) {
          root.stampSeq++
          starts[name] = root.stampSeq
          changed = true
        }
        if (lasts[name] !== starts[name]) {
          lasts[name] = starts[name]
          changed = true
        }
      } else if (starts[name]) {
        starts[name] = 0
        changed = true
      }
    }

    if (changed) {
      root.startStamps = starts
      root.lastStamps = lasts
    }

    // Drop a pin whose player has gone away.
    if (root.pinnedDbusName !== "") {
      var stillThere = false
      for (var j = 0; j < list.length; j++)
        if (list[j].dbusName === root.pinnedDbusName)
          stillThere = true
      if (!stillThere)
        root.pinnedDbusName = ""
    }
  }

  function pinPlayer(dbusName) {
    root.pinnedDbusName = root.pinnedDbusName === dbusName ? "" : dbusName
  }

  // --- track identity --------------------------------------------------------

  readonly property bool hasTrack: active !== null && active.trackTitle !== ""

  readonly property string trackTitle: active ? active.trackTitle : ""
  readonly property string trackArtist: active ? active.trackArtist : ""
  readonly property string trackAlbum: active ? active.trackAlbum : ""
  readonly property string trackArtUrl: active ? active.trackArtUrl : ""
  readonly property real length: active && active.lengthSupported ? active.length : 0
  readonly property string sourceLabel: active ? active.identity : "No player"

  // Stable key for lyrics lookup and caching. Changes exactly when the track
  // changes, so it is what LyricsState watches.
  readonly property string trackKey: hasTrack
    ? [trackArtist, trackTitle, trackAlbum, Math.round(length)].join("|")
    : ""

  // --- position --------------------------------------------------------------

  // MprisPlayer.position does not update on its own. Keep a base sample and
  // extrapolate from it, resyncing on every signal that could invalidate it.
  // This yields sub-second accuracy for lyric timing with almost no D-Bus
  // traffic, and keeps working even if forcing a refresh is unavailable.
  property real positionBase: 0
  property real positionBaseMs: 0
  property real effectivePosition: 0
  property bool dragging: false

  readonly property real progress: length > 0
    ? Math.max(0, Math.min(1, effectivePosition / length)) : 0

  function resyncPosition() {
    const p = root.active
    if (!p) {
      root.positionBase = 0
      root.positionBaseMs = Date.now()
      root.effectivePosition = 0
      return
    }
    root.positionBase = p.positionSupported ? p.position : 0
    root.positionBaseMs = Date.now()
    root.effectivePosition = root.positionBase
  }

  Connections {
    target: root.active
    ignoreUnknownSignals: true
    function onPositionChanged() { if (!root.dragging) root.resyncPosition() }
    function onPlaybackStateChanged() { root.resyncPosition() }
    function onTrackChanged() { root.resyncPosition() }
    function onLengthChanged() { root.resyncPosition() }
  }

  onActiveChanged: root.resyncPosition()

  // Smooth local extrapolation for the timeline and lyric sync.
  // Only while the panel shows the timeline and lyrics; nothing else reads it.
  Timer {
    interval: 100
    repeat: true
    triggeredOnStart: true
    running: root.panelVisible && root.active !== null && root.active.isPlaying && !root.dragging
    onTriggered: {
      const p = root.active
      if (!p)
        return
      const rate = p.rate > 0 ? p.rate : 1
      root.effectivePosition = root.positionBase
        + (Date.now() - root.positionBaseMs) / 1000 * rate
    }
  }

  // Periodic true re-read so extrapolation cannot drift.
  Timer {
    interval: 2000
    repeat: true
    triggeredOnStart: true
    running: root.panelVisible && root.active !== null && root.active.isPlaying
    onTriggered: {
      const p = root.active
      if (!p || root.dragging)
        return
      // Quickshell documents emitting positionChanged() to force a refresh.
      // Guarded because it is the one part of this API not verifiable offline;
      // without it we simply keep extrapolating from the last known sample.
      try {
        p.positionChanged()
      } catch (e) {
        // ignored on purpose -- resync below still re-reads the property
      }
      root.resyncPosition()
    }
  }

  // --- seeking ---------------------------------------------------------------

  readonly property bool canSeek: active !== null && active.canSeek
                               && active.lengthSupported && length > 0

  property real pendingSeek: -1

  // Updates the local position immediately so the handle tracks the cursor,
  // and debounces the actual seek so a scrub does not flood the player.
  function seekToFraction(fraction) {
    if (!root.canSeek)
      return
    const frac = Math.max(0, Math.min(1, fraction))
    root.positionBase = frac * root.length
    root.positionBaseMs = Date.now()
    root.effectivePosition = root.positionBase
    root.pendingSeek = frac
    seekTimer.restart()
  }

  Timer {
    id: seekTimer
    interval: 80
    repeat: false
    onTriggered: {
      const p = root.active
      if (!p || root.pendingSeek < 0)
        return
      p.position = root.pendingSeek * root.length
      root.pendingSeek = -1
    }
  }

  // --- controls --------------------------------------------------------------

  readonly property bool canNext: active !== null && active.canGoNext
  readonly property bool canPrevious: active !== null && active.canGoPrevious
  readonly property bool canTogglePlaying: active !== null && active.canTogglePlaying
  readonly property bool loopSupported: active !== null && active.loopSupported
  readonly property bool shuffleSupported: active !== null && active.shuffleSupported
  readonly property bool volumeSupported: active !== null && active.volumeSupported
  readonly property bool canRaise: active !== null && active.canRaise
  readonly property bool isPlaying: active !== null && active.isPlaying
  readonly property bool shuffle: active !== null && active.shuffle
  readonly property real volume: active !== null && active.volumeSupported ? active.volume : 0

  function next() { if (canNext) active.next() }
  function previous() { if (canPrevious) active.previous() }
  function togglePlaying() { if (canTogglePlaying) active.togglePlaying() }
  function stop() { if (active) active.stop() }
  function raisePlayer() { if (canRaise) active.raise() }
  function setVolume(v) {
    if (volumeSupported)
      active.volume = Math.max(0, Math.min(1, v))
  }
  function toggleShuffle() {
    if (shuffleSupported)
      active.shuffle = !active.shuffle
  }
  function cycleLoop() {
    if (!loopSupported)
      return
    if (active.loopState === MprisLoopState.None)
      active.loopState = MprisLoopState.Playlist
    else if (active.loopState === MprisLoopState.Playlist)
      active.loopState = MprisLoopState.Track
    else
      active.loopState = MprisLoopState.None
  }

  // --- glyphs (codepoints verified against the installed Nerd Font cmap) -----

  readonly property string glyphMusic: String.fromCodePoint(0xf075a)    // md-music
  readonly property string glyphPrevious: String.fromCodePoint(0xf04ae) // md-skip_previous
  readonly property string glyphNext: String.fromCodePoint(0xf04ad)     // md-skip_next
  readonly property string glyphStop: String.fromCodePoint(0xf04db)     // md-stop
  readonly property string glyphOpen: String.fromCodePoint(0xf03cc)     // md-open_in_new
  readonly property string glyphSpotify: String.fromCodePoint(0xf04c7)  // md-spotify
  readonly property string glyphVolume: String.fromCodePoint(0xf057e)   // md-volume_high

  readonly property string playGlyph: isPlaying
    ? String.fromCodePoint(0xf03e4)  // md-pause
    : String.fromCodePoint(0xf040a)  // md-play

  readonly property string loopGlyph: {
    if (!active)
      return String.fromCodePoint(0xf0456) // md-repeat
    if (active.loopState === MprisLoopState.Track)
      return String.fromCodePoint(0xf0458) // md-repeat_once
    if (active.loopState === MprisLoopState.Playlist)
      return String.fromCodePoint(0xf0456) // md-repeat
    return String.fromCodePoint(0xf0457)   // md-repeat_off
  }

  readonly property bool loopActive: active !== null
    && active.loopState !== MprisLoopState.None

  readonly property string shuffleGlyph: shuffle
    ? String.fromCodePoint(0xf049d)  // md-shuffle
    : String.fromCodePoint(0xf049e)  // md-shuffle_disabled

  // Source glyph: Spotify gets its own mark, anything else the generic note.
  readonly property string sourceGlyph:
    (active && active.dbusName.indexOf("spotify") !== -1)
      ? glyphSpotify : glyphMusic

  // --- helpers ---------------------------------------------------------------

  function formatTime(seconds) {
    if (!isFinite(seconds) || seconds < 0)
      return "0:00"
    const total = Math.floor(seconds)
    const m = Math.floor(total / 60)
    const s = total % 60
    return m + ":" + (s < 10 ? "0" + s : "" + s)
  }
}
