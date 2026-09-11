pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import "AudioHelpers.js" as AudioHelpers

Singleton {
  id: root

  property bool panelVisible: false
  // Connector name of the screen whose bar opened the panel. Each bar
  // instance builds its own popup, so without this the panel would try to
  // open on every monitor at once instead of the one that was clicked.
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

  readonly property PwNode sink: Pipewire.defaultAudioSink
  readonly property PwNode source: Pipewire.defaultAudioSource
  readonly property bool available: Pipewire.ready

  // Hardware output devices. Per the docs, isSink === true means the node
  // *accepts* audio (i.e. it is an output device); false means it produces
  // audio (an input). isStream filters out application streams.
  readonly property var sinks: Pipewire.nodes.values.filter(
    n => AudioHelpers.isOutputDevice(n))
  readonly property var sources: Pipewire.nodes.values.filter(
    n => AudioHelpers.isInputDevice(n))
  // Playback streams produce audio, so unlike hardware output devices they
  // have isSink === false. Recording streams accept audio and are excluded.
  readonly property var streams: Pipewire.nodes.values.filter(
    n => AudioHelpers.isPlaybackStream(n))

  // audio.* properties are invalid until the node is bound, so track both the
  // active devices and every device offered in the switcher lists.
  PwObjectTracker {
    objects: {
      const list = []
      if (root.sink) list.push(root.sink)
      if (root.source) list.push(root.source)
      return list.concat(root.sinks).concat(root.sources).concat(root.streams)
    }
  }

  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
  readonly property int volumePct: sink && sink.audio
    ? AudioHelpers.volumePercent(sink.audio.volume) : 0
  readonly property int inputVolumePct: source && source.audio
    ? AudioHelpers.volumePercent(source.audio.volume) : 0
  readonly property bool inputMuted: source && source.audio ? source.audio.muted : false

  // Four volume tiers plus a muted state. Codepoints verified against the
  // installed JetBrainsMono Nerd Font cmap.
  readonly property string glyph: {
    if (muted || volumePct === 0)
      return String.fromCodePoint(0xf0581) // md-volume_off (speaker + X)
    if (volumePct <= 25)
      return String.fromCodePoint(0xf057f) // md-volume_low
    if (volumePct <= 70)
      return String.fromCodePoint(0xf0580) // md-volume_medium
    return String.fromCodePoint(0xf057e)   // md-volume_high
  }

  function deviceLabel(node) {
    if (!node)
      return "None"
    return node.nickname || node.description || node.name || "Unknown"
  }

  function deviceName(node) {
    return node && node.name ? String(node.name) : ""
  }

  function deviceDescription(node) {
    return AudioHelpers.deviceDescription(node)
  }

  // Quickshell exposes PipeWire's node property map rather than a dedicated
  // port model. Use only documented node properties, in preference order.
  function deviceDetail(node) {
    return AudioHelpers.deviceDetail(node)
  }

  function desktopEntryFor(node) {
    return AudioHelpers.desktopEntryFor(node, DesktopEntries)
  }

  function streamLabel(node) {
    return AudioHelpers.streamLabel(node)
  }

  function streamIcon(node) {
    const props = node && node.properties ? node.properties : ({})
    const entry = root.desktopEntryFor(node)
    const iconName = String(props["application.icon-name"]
      || (entry ? entry.icon : "") || "").trim()
    return iconName === "" ? "" : Quickshell.iconPath(iconName, true)
  }

  function streamVolumePct(node) {
    return node && node.audio ? AudioHelpers.volumePercent(node.audio.volume) : 0
  }

  function setVolume(fraction) {
    if (!sink || !sink.audio)
      return
    sink.audio.volume = AudioHelpers.clampVolume(fraction)
  }

  function stepVolume(delta) {
    if (!sink || !sink.audio)
      return
    sink.audio.volume = AudioHelpers.clampVolume(sink.audio.volume + delta)
  }

  function setInputVolume(fraction) {
    if (!source || !source.audio)
      return
    source.audio.volume = AudioHelpers.clampVolume(fraction)
  }

  function setStreamVolume(node, fraction) {
    if (!node || !node.audio)
      return
    node.audio.volume = AudioHelpers.clampVolume(fraction)
  }

  function toggleStreamMute(node) {
    if (!node || !node.audio)
      return
    node.audio.muted = !node.audio.muted
  }

  function toggleMute() {
    if (!sink || !sink.audio)
      return
    sink.audio.muted = !sink.audio.muted
  }

  function setSink(node) {
    if (node)
      Pipewire.preferredDefaultAudioSink = node
  }

  function setSource(node) {
    if (node)
      Pipewire.preferredDefaultAudioSource = node
  }
}
