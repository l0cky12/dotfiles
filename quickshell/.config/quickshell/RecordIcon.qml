import QtQuick

// Bar item: appears only while a screen recording is running. Clicking it stops
// the recording, which is the only thing anyone wants from it mid-capture.
//
// Filled with Theme.error rather than Theme.accent so it reads as "something is
// live" instead of blending in with the other active-state icons, and slowly
// pulses so it stays noticeable without being a distraction on screen -- it is
// visible in the recording itself.
Item {
  id: root

  // Bar chrome scale, passed down from Bar.qml.
  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }

  // A Row skips invisible children, so the bar closes up when idle.
  visible: RecordState.recording

  implicitWidth: label.implicitWidth + root.s(16)
  implicitHeight: label.implicitHeight + root.s(6)

  Rectangle {
    id: pill
    anchors.fill: parent
    radius: Theme.radiusCell
    color: Theme.error

    // A two-state blink, not an eased pulse: a running animation re-renders
    // every bar at the display refresh rate for the whole recording, competing
    // with the encoder; this repaints twice per cycle.
    property bool dim: false
    opacity: dim ? 0.55 : 1.0
    Timer {
      interval: 900
      repeat: true
      running: root.visible
      onTriggered: pill.dim = !pill.dim
      onRunningChanged: if (!running) pill.dim = false
    }
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: RecordState.glyphRecord
    font.family: Theme.glyphFamily
    font.pixelSize: root.s(15)
    color: Theme.bgDeep
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onClicked: RecordState.stop()
  }
}
