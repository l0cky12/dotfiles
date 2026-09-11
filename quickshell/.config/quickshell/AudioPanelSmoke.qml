import Quickshell
import QtQuick
import "AudioHelpers.js" as AudioHelpers

// Headless render fixture for the real AudioPanel content. It deliberately
// avoids constructing PopupWindow, which requires a live Wayland compositor.
Scope {
  id: smoke
  property int failures: 0

  QtObject { id: outputOneAudio; property real volume: 0.64; property bool muted: false }
  QtObject { id: outputTwoAudio; property real volume: 0.42; property bool muted: false }
  QtObject { id: inputAudio; property real volume: 0.71; property bool muted: false }
  QtObject { id: browserAudio; property real volume: 0.55; property bool muted: false }
  QtObject { id: playerAudio; property real volume: 0.28; property bool muted: true }

  QtObject {
    id: outputOne
    property bool isSink: true
    property bool isStream: false
    property string name: "alsa_output.usb-dac"
    property string description: "Desk DAC"
    property string nickname: ""
    property var properties: ({ "device.description": "Desk DAC profile" })
    property QtObject audio: outputOneAudio
  }
  QtObject {
    id: outputTwo
    property bool isSink: true
    property bool isStream: false
    property string name: "bluez_output.headphones"
    property string description: "Wireless Headphones"
    property string nickname: ""
    property var properties: ({})
    property QtObject audio: outputTwoAudio
  }
  QtObject {
    id: inputOne
    property bool isSink: false
    property bool isStream: false
    property string name: "alsa_input.usb-mic"
    property string description: "USB Microphone"
    property string nickname: ""
    property var properties: ({ "node.description": "USB microphone profile" })
    property QtObject audio: inputAudio
  }
  QtObject {
    id: browserStream
    property bool isSink: false
    property bool isStream: true
    property string name: "Firefox"
    property string description: "Browser playback"
    property string nickname: ""
    property var properties: ({ "application.name": "Firefox", "application.icon-name": "firefox" })
    property QtObject audio: browserAudio
  }
  QtObject {
    id: playerStream
    property bool isSink: false
    property bool isStream: true
    property string name: "Music"
    property string description: "Music playback"
    property string nickname: ""
    property var properties: ({ "application.name": "Music" })
    property QtObject audio: playerAudio
  }

  QtObject {
    id: fixture
    property bool available: true
    property bool panelVisible: true
    property string panelScreen: "smoke"
    property var sink: outputOne
    property var source: inputOne
    property var nodes: [outputOne, outputTwo, inputOne, browserStream, playerStream]
    property var sinks: nodes.filter(node => AudioHelpers.isOutputDevice(node))
    property var sources: nodes.filter(node => AudioHelpers.isInputDevice(node))
    property var streams: nodes.filter(node => AudioHelpers.isPlaybackStream(node))
    property bool muted: outputOneAudio.muted
    property int volumePct: AudioHelpers.volumePercent(outputOneAudio.volume)
    property int inputVolumePct: AudioHelpers.volumePercent(inputAudio.volume)
    property string glyph: String.fromCodePoint(0xf057e)

    function deviceName(node) { return node && node.name ? node.name : "" }
    function deviceDescription(node) { return AudioHelpers.deviceDescription(node) }
    function deviceDetail(node) { return AudioHelpers.deviceDetail(node) }
    function streamLabel(node) { return AudioHelpers.streamLabel(node) }
    function streamIcon(node) { return "" }
    function streamVolumePct(node) { return AudioHelpers.volumePercent(node.audio.volume) }
    function setVolume(value) { sink.audio.volume = AudioHelpers.clampVolume(value) }
    function setInputVolume(value) { source.audio.volume = AudioHelpers.clampVolume(value) }
    function setStreamVolume(node, value) { node.audio.volume = AudioHelpers.clampVolume(value) }
    function toggleMute() { sink.audio.muted = !sink.audio.muted }
    function toggleStreamMute(node) { node.audio.muted = !node.audio.muted }
    function setSink(node) { sink = node }
    function setSource(node) { source = node }
  }

  Item {
    width: Theme.fs(412)
    height: panelContent.implicitHeight

    AudioPanelContent {
      id: panelContent
      width: parent.width
      audio: fixture
    }
  }

  function check(name, condition) {
    if (condition)
      console.log("ok   " + name)
    else {
      console.log("FAIL " + name)
      failures += 1
    }
  }

  function findObject(item, name) {
    if (!item)
      return null
    if (item.objectName === name)
      return item
    const children = item.children || []
    for (let i = 0; i < children.length; ++i) {
      const found = findObject(children[i], name)
      if (found)
        return found
    }
    return null
  }

  Timer {
    interval: 300
    running: true
    onTriggered: {
      const output0 = smoke.findObject(panelContent, "audio-output-row-0")
      const output1 = smoke.findObject(panelContent, "audio-output-row-1")
      const input0 = smoke.findObject(panelContent, "audio-input-row-0")
      const stream0 = smoke.findObject(panelContent, "audio-stream-row-0")
      const stream1 = smoke.findObject(panelContent, "audio-stream-row-1")
      const inputVolume = smoke.findObject(panelContent, "audio-input-volume")

      smoke.check("renders both output devices", output0 && output1)
      smoke.check("renders device descriptions",
        output0 && output0.deviceTitle === "Desk DAC"
        && output1 && output1.deviceTitle === "Wireless Headphones")
      smoke.check("marks only the default output active",
        output0 && output0.activeDevice && output1 && !output1.activeDevice)
      smoke.check("renders the input device active", input0 && input0.activeDevice)
      smoke.check("renders both playback streams", stream0 && stream1)
      smoke.check("projects application names",
        stream0 && stream0.applicationTitle === "Firefox"
        && stream1 && stream1.applicationTitle === "Music")
      smoke.check("projects per-stream mute state",
        stream0 && !stream0.streamMuted && stream1 && stream1.streamMuted)
      smoke.check("renders documented node metadata",
        output0 && output0.deviceDetail === "Desk DAC profile")
      smoke.check("renders master input volume", inputVolume && inputVolume.visible)
      smoke.check("does not show the empty state with fixture rows", !panelContent.isEmpty)

      fixture.available = false
      fixture.sink = null
      fixture.source = null
      fixture.nodes = []
      emptyTimer.start()
    }
  }

  Timer {
    id: emptyTimer
    interval: 100
    onTriggered: {
      const emptyState = smoke.findObject(panelContent, "audio-empty-state")
      const status = smoke.findObject(panelContent, "audio-status")
      smoke.check("renders empty lists", panelContent.isEmpty && emptyState.visible)
      smoke.check("labels initial PipeWire sync neutrally",
        status.text === "PipeWire syncing…"
        && emptyState.unavailableText === "PipeWire syncing…"
        && emptyState.unavailable)

      fixture.available = true
      readyTimer.start()
    }
  }

  Timer {
    id: readyTimer
    interval: 100
    onTriggered: {
      const emptyState = smoke.findObject(panelContent, "audio-empty-state")
      const emptyMessage = smoke.findObject(panelContent, "audio-empty-message")
      smoke.check("labels a synced empty device list neutrally",
        emptyState.visible && !emptyState.unavailable
        && emptyMessage && emptyMessage.text === "No audio devices")

      console.log(smoke.failures === 0
        ? "ok: AudioPanel fixture rendering"
        : "FAIL: " + smoke.failures + " assertion(s) failed")
      Qt.quit()
    }
  }
}
