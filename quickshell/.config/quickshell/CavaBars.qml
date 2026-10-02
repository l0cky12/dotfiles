import QtQuick

Item {
  id: root

  property bool active: true
  property real spacing: Theme.fs(3)
  property real minimumHeight: Theme.fs(2)
  property color barColor: Theme.accent

  implicitHeight: Theme.fs(48)

  Row {
    anchors.fill: parent
    spacing: root.spacing

    Repeater {
      // A count, not the levels array: an array model rebuilds every delegate
      // on each 30 fps frame, while this updates only the heights.
      model: CavaState.barCount

      Rectangle {
        required property int index
        readonly property real modelData: CavaState.levels[index] || 0
        width: Math.max(1, (root.width - root.spacing * (CavaState.barCount - 1))
                        / CavaState.barCount)
        height: root.active && CavaState.available
                ? Math.max(root.minimumHeight, modelData * root.height)
                : root.minimumHeight
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        color: root.barColor
      }
    }
  }
}
