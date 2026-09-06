import QtQuick

Item {
  id: root

  property real mbps: 0
  property string label: ""
  property bool running: false
  property real probeFraction: 0
  property color accentColor: Theme.accent
  property color trackColor: Theme.surfaceAlt

  readonly property real resultFraction: SpeedTestState.gaugeFraction(root.mbps)
  readonly property real dialFraction: root.running ? root.probeFraction : root.resultFraction

  implicitWidth: Theme.fs(330)
  implicitHeight: Theme.fs(285)

  SequentialAnimation on probeFraction {
    running: root.running
    loops: Animation.Infinite
    NumberAnimation { from: 0.03; to: 0.78; duration: 1050; easing.type: Easing.InOutCubic }
    NumberAnimation { to: 0.22; duration: 620; easing.type: Easing.OutCubic }
    NumberAnimation { to: 0.92; duration: 900; easing.type: Easing.InOutCubic }
    NumberAnimation { to: 0.08; duration: 700; easing.type: Easing.OutCubic }
  }

  Canvas {
    id: dial
    anchors.fill: parent

    property real fraction: root.dialFraction
    property color accent: root.accentColor
    property color track: root.trackColor
    onFractionChanged: requestPaint()
    onAccentChanged: requestPaint()
    onTrackChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      const ctx = getContext("2d")
      ctx.reset()
      const cx = width / 2
      const cy = height * 0.58
      const radius = Math.min(width * 0.39, height * 0.43)
      const start = Math.PI * 0.75
      const sweep = Math.PI * 1.5

      ctx.lineCap = "round"
      ctx.lineWidth = Math.max(2, Theme.fs(3))
      ctx.strokeStyle = track
      ctx.beginPath()
      ctx.arc(cx, cy, radius, start, start + sweep)
      ctx.stroke()

      for (let index = 0; index <= 24; index++) {
        const angle = start + sweep * index / 24
        const major = index % 4 === 0
        const outer = radius - Theme.fs(7)
        const inner = outer - Theme.fs(major ? 15 : 9)
        ctx.lineWidth = Math.max(1, Theme.fs(major ? 2 : 1))
        ctx.strokeStyle = index / 24 <= fraction ? accent : track
        ctx.beginPath()
        ctx.moveTo(cx + Math.cos(angle) * inner, cy + Math.sin(angle) * inner)
        ctx.lineTo(cx + Math.cos(angle) * outer, cy + Math.sin(angle) * outer)
        ctx.stroke()
      }

      const needleAngle = start + sweep * fraction
      const needleLength = radius - Theme.fs(34)
      ctx.lineWidth = Math.max(2, Theme.fs(4))
      ctx.strokeStyle = accent
      ctx.beginPath()
      ctx.moveTo(cx, cy)
      ctx.lineTo(cx + Math.cos(needleAngle) * needleLength,
                 cy + Math.sin(needleAngle) * needleLength)
      ctx.stroke()
      ctx.fillStyle = accent
      ctx.beginPath()
      ctx.arc(cx, cy, Theme.fs(7), 0, Math.PI * 2)
      ctx.fill()
    }
  }

  Column {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: Theme.fs(42)
    spacing: 0

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.running ? "…" : SpeedTestState.formatMbps(root.mbps)
      color: Theme.text
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(31)
      font.bold: true
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Mbps"
      color: Theme.textMuted
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(11)
    }
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    text: root.label.toUpperCase()
    color: root.accentColor
    font.family: Theme.glyphFamily
    font.pixelSize: Theme.fs(12)
    font.bold: true
    font.letterSpacing: Theme.fs(2)
  }
}
