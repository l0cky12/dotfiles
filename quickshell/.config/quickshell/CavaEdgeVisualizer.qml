import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
  id: panel
  required property var output
  property bool anchorTop: false
  screen: output

  visible: VisualizerState.visible
  // Keep the desktop spectrum present but unobtrusive, like a playback line
  // stretched along the edge rather than a tall equalizer panel.
  implicitHeight: Theme.fs(48)
  color: "transparent"
  anchors {
    top: panel.anchorTop
    bottom: !panel.anchorTop
    left: true
    right: true
  }
  exclusionMode: ExclusionMode.Ignore
  mask: Region {}
  WlrLayershell.namespace: panel.anchorTop
                           ? "quickshell-cava-top" : "quickshell-cava-bottom"
  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  // Repaint when cava delivers a frame (it already caps itself at 30 fps) or
  // when playback state changes. A free-running timer repainted both
  // full-width canvases 30 times a second even while paused.
  Connections {
    target: CavaState
    enabled: panel.visible
    function onLevelsChanged() { canvas.requestPaint() }
    function onAvailableChanged() { canvas.requestPaint() }
  }
  Connections {
    target: MediaState
    enabled: panel.visible
    function onIsPlayingChanged() { canvas.requestPaint() }
  }
  onVisibleChanged: if (visible) canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent

    onPaint: {
      const ctx = getContext("2d")
      const w = width
      const h = height
      const baseline = panel.anchorTop ? 0.5 : h - 1.5
      ctx.clearRect(0, 0, w, h)
      ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.9)
      ctx.lineWidth = 2
      ctx.beginPath()
      ctx.moveTo(0, baseline)
      ctx.lineTo(w, baseline)
      ctx.stroke()

      if (!CavaState.available || !MediaState.isPlaying || CavaState.levels.length === 0)
        return

      ctx.fillStyle = Qt.rgba(1, 1, 1, 0.9)
      const step = w / (CavaState.levels.length - 1)
      const yFor = level => panel.anchorTop
                            ? baseline + Math.max(2, level * (h - 5))
                            : baseline - Math.max(2, level * (h - 5))
      ctx.beginPath()
      ctx.moveTo(0, baseline)
      ctx.lineTo(0, yFor(CavaState.levels[0]))
      for (let i = 0; i < CavaState.levels.length - 1; i++) {
        const x = i * step
        const nextX = (i + 1) * step
        ctx.quadraticCurveTo(x, yFor(CavaState.levels[i]),
                             (x + nextX) / 2,
                             (yFor(CavaState.levels[i]) + yFor(CavaState.levels[i + 1])) / 2)
      }
      ctx.lineTo(w, yFor(CavaState.levels[CavaState.levels.length - 1]))
      ctx.lineTo(w, baseline)
      ctx.closePath()
      ctx.fill()
    }
  }
}
