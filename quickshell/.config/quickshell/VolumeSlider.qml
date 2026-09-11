import QtQuick

// Minimal draggable slider. `value` is a 0..1 fraction; `moved` fires with the
// new fraction on press and drag.
Item {
  id: root
  property real value: 0
  signal moved(real fraction)

  // Tintable so other panels can reuse the slider without duplicating it.
  property color trackColor: Theme.surface
  property color fillColor: Theme.accent
  property color knobColor: Theme.text

  // Lets callers suppress incoming value updates while the user scrubs, so the
  // handle does not fight an external source of truth (e.g. a media player's
  // playback position).
  readonly property bool dragging: dragArea.pressed
  signal released(real fraction)

  implicitWidth: 200
  implicitHeight: 16

  readonly property real clamped: Math.max(0, Math.min(1, value))

  function emitFromX(x) {
    if (width <= 0)
      return
    root.moved(Math.max(0, Math.min(1, x / width)))
  }

  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: 5
    radius: 3
    color: root.trackColor

    Rectangle {
      width: root.clamped * parent.width
      height: parent.height
      radius: 3
      color: root.fillColor
    }
  }

  Rectangle {
    width: 12
    height: 12
    radius: 6
    color: root.knobColor
    anchors.verticalCenter: parent.verticalCenter
    x: root.clamped * (root.width - width)
  }

  MouseArea {
    id: dragArea
    anchors.fill: parent
    preventStealing: true
    onPressed: mouse => root.emitFromX(mouse.x)
    onPositionChanged: mouse => {
      if (pressed)
        root.emitFromX(mouse.x)
    }
    onReleased: mouse => {
      if (root.width > 0)
        root.released(Math.max(0, Math.min(1, mouse.x / root.width)))
    }
  }
}
