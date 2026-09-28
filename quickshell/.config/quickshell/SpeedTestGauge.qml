import QtQuick

Item {
  id: root

  property real value: 0
  property real peak: 0
  property bool active: false
  property string label: ""
  // Defaults suit the network speed test; the disk speed test passes MB/s
  // and its own steps. detail is an optional line under the label.
  property string unit: "Mbps"
  property var scaleSteps: [10, 25, 50, 100, 200, 400, 800, 1600, 3200, 6400]
  property string detail: ""
  property int diameter: Theme.fs(280)
  property real shownValue: value

  implicitWidth: diameter
  implicitHeight: diameter + Theme.fs(34) + (detail === "" ? 0 : Theme.fs(18))

  function scaleFor(amount) {
    const steps = scaleSteps
    const target = Math.max(0, Number(amount) || 0)
    for (let i = 0; i < steps.length; i++)
      if (target <= steps[i])
        return steps[i]
    const last = steps[steps.length - 1]
    return Math.ceil(target / last) * last
  }

  readonly property real scale: scaleFor(Math.max(value, peak))
  readonly property real ratio: Math.max(0, Math.min(1, shownValue / scale))

  Behavior on shownValue {
    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
  }

  Canvas {
    id: dial
    width: root.diameter
    height: root.diameter

    property color accent: Theme.info
    property color track: Theme.textMuted
    property color text: Theme.text
    property real value: root.shownValue
    property real ratio: root.ratio
    property bool active: root.active

    onAccentChanged: requestPaint()
    onTrackChanged: requestPaint()
    onTextChanged: requestPaint()
    onValueChanged: requestPaint()
    onRatioChanged: requestPaint()
    onActiveChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      const ctx = getContext("2d")
      ctx.reset()
      const cx = width / 2
      const cy = height / 2
      const radius = width * 0.385
      const start = Math.PI * 0.75
      const sweep = Math.PI * 1.5
      const ink = active ? accent : track
      const tickInk = Qt.rgba(track.r, track.g, track.b, active ? 0.62 : 0.36)

      ctx.lineCap = "round"
      ctx.lineWidth = Theme.fs(3)
      ctx.strokeStyle = Qt.rgba(track.r, track.g, track.b, active ? 0.58 : 0.34)
      ctx.beginPath()
      ctx.arc(cx, cy, radius, start, start + sweep)
      ctx.stroke()

      ctx.lineWidth = Theme.fs(1)
      ctx.strokeStyle = tickInk
      for (let tick = 0; tick <= 36; tick++) {
        const angle = start + sweep * tick / 36
        const outer = radius + Theme.fs(13)
        const inner = outer - Theme.fs(tick % 6 === 0 ? 8 : 5)
        ctx.beginPath()
        ctx.moveTo(cx + Math.cos(angle) * inner, cy + Math.sin(angle) * inner)
        ctx.lineTo(cx + Math.cos(angle) * outer, cy + Math.sin(angle) * outer)
        ctx.stroke()
      }

      if (active && ratio > 0) {
        ctx.lineWidth = Theme.fs(5)
        ctx.strokeStyle = ink
        ctx.beginPath()
        ctx.arc(cx, cy, radius, start, start + sweep * ratio)
        ctx.stroke()
      }

      const needleAngle = start + sweep * ratio
      const needleLength = radius * 0.78
      ctx.lineWidth = Theme.fs(3)
      ctx.strokeStyle = Qt.rgba(ink.r, ink.g, ink.b, active ? 1 : 0.58)
      ctx.beginPath()
      ctx.moveTo(cx, cy)
      ctx.lineTo(cx + Math.cos(needleAngle) * needleLength,
                 cy + Math.sin(needleAngle) * needleLength)
      ctx.stroke()
      ctx.fillStyle = ctx.strokeStyle
      ctx.beginPath()
      ctx.arc(cx, cy, Theme.fs(4), 0, Math.PI * 2)
      ctx.fill()
    }
  }

  Column {
    anchors.centerIn: dial
    anchors.verticalCenterOffset: Theme.fs(18)
    spacing: Theme.fs(2)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.shownValue.toFixed(1)
      color: root.active ? Theme.text : Theme.textMuted
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(34)
      font.bold: true
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.unit
      color: Theme.textMuted
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(12)
    }
  }

  Text {
    id: caption
    anchors.top: dial.bottom
    anchors.topMargin: Theme.fs(8)
    anchors.horizontalCenter: parent.horizontalCenter
    text: root.label.toUpperCase()
    color: root.active ? Theme.info : Theme.textMuted
    font.family: Theme.glyphFamily
    font.pixelSize: Theme.fs(12)
    font.letterSpacing: Theme.fs(2)
  }

  Text {
    anchors.top: caption.bottom
    anchors.topMargin: Theme.fs(4)
    anchors.horizontalCenter: parent.horizontalCenter
    visible: root.detail !== ""
    text: root.detail
    color: Theme.textMuted
    font.family: Theme.glyphFamily
    font.pixelSize: Theme.fs(11)
  }
}
