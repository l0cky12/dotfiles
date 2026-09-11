pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

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
    n => n && n.audio && n.isSink && !n.isStream)
  readonly property var sources: Pipewire.nodes.values.filter(
    n => n && n.audio && !n.isSink && !n.isStream)
  // Playback streams produce audio, so unlike hardware output devices they
  // have isSink === false. Recording streams accept audio and are excluded.
  readonly property var streams: Pipewire.nodes.values.filter(
    n => n && n.audio && n.isStream && !n.isSink)

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
    ? Math.round(sink.audio.volume * 100) : 0
  readonly property int inputVolumePct: source && source.audio
    ? Math.round(source.audio.volume * 100) : 0
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
    if (!node)
      return "Unknown"
    return node.description || node.nickname || node.name || "Unknown"
  }

  function nodeProperties(node) {
    return node && node.properties ? node.properties : ({})
  }

  // Quickshell exposes PipeWire's node property map rather than a dedicated
  // port model. Surface the port/profile fields when the backend publishes
  // them, de-duplicated because some devices use the same value for both.
  function devicePorts(node) {
    const props = root.nodeProperties(node)
    const candidates = [
      props["port.alias"],
      props["port.name"],
      props["device.profile.description"],
      props["device.profile.name"]
    ]
    const ports = []
    for (const candidate of candidates) {
      const value = String(candidate || "").trim()
      if (value !== "" && ports.indexOf(value) < 0)
        ports.push(value)
    }
    return ports
  }

  function desktopEntryFor(node) {
    const props = root.nodeProperties(node)
    const desktopId = String(props["application.desktop-entry"] || "").trim()
    if (desktopId !== "") {
      const exact = DesktopEntries.byId(desktopId)
        || DesktopEntries.byId(desktopId.replace(/\.desktop$/, ""))
      if (exact)
        return exact
    }

    const lookup = String(props["application.name"]
      || props["application.process.binary"] || root.deviceLabel(node)).trim()
    return lookup === "" ? null : DesktopEntries.heuristicLookup(lookup)
  }

  function streamLabel(node) {
    const entry = root.desktopEntryFor(node)
    if (entry && entry.name)
      return entry.name
    const props = root.nodeProperties(node)
    return String(props["application.name"] || props["application.process.binary"]
      || node.description || node.nickname || node.name || "Application")
  }

  function streamIcon(node) {
    const props = root.nodeProperties(node)
    const entry = root.desktopEntryFor(node)
    const iconName = String(props["application.icon-name"]
      || (entry ? entry.icon : "") || "").trim()
    return iconName === "" ? "" : Quickshell.iconPath(iconName, true)
  }

  function streamVolumePct(node) {
    return node && node.audio ? Math.round(node.audio.volume * 100) : 0
  }

  function setVolume(fraction) {
    if (!sink || !sink.audio)
      return
    sink.audio.volume = Math.max(0, Math.min(1, fraction))
  }

  function stepVolume(delta) {
    if (!sink || !sink.audio)
      return
    sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + delta))
  }

  function setInputVolume(fraction) {
    if (!source || !source.audio)
      return
    source.audio.volume = Math.max(0, Math.min(1, fraction))
  }

  function setStreamVolume(node, fraction) {
    if (!node || !node.audio)
      return
    node.audio.volume = Math.max(0, Math.min(1, fraction))
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
