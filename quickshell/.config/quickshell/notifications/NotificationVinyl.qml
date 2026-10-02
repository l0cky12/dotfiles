import QtQuick
import QtQuick.Effects
import ".."

// Album sleeve with a record sliding out to the right. The record spins while
// the active MPRIS player is playing, so a paused track reads as paused.
Item {
  id: root

  property string source: ""
  property int sleeveSize: Theme.fs(NotificationConfig.iconSize)
  property bool spinning: MediaState.isPlaying

  readonly property int discSize: Math.round(sleeveSize * 0.94)
  readonly property int discOffset: Math.round(sleeveSize * 0.55)

  implicitWidth: discOffset + discSize
  implicitHeight: sleeveSize

  Rectangle {
    id: disc
    x: root.discOffset
    anchors.verticalCenter: parent.verticalCenter
    width: root.discSize
    height: root.discSize
    radius: width / 2
    color: "#111111"

    // Grooves: a few concentric hairlines are enough to read as vinyl.
    Repeater {
      model: 3
      Rectangle {
        required property int index
        anchors.centerIn: parent
        width: disc.width - Theme.fs(4) * (index + 1) * 1.6
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.07)
      }
    }

    // Centre label: the album art, clipped to a circle.
    Item {
      id: label
      anchors.centerIn: parent
      width: Math.round(disc.width * 0.42)
      height: width

      Image {
        id: labelArt
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        visible: false
      }

      Rectangle {
        id: labelMask
        anchors.fill: parent
        radius: width / 2
        visible: false
        layer.enabled: true
      }

      MultiEffect {
        anchors.fill: parent
        source: labelArt
        maskEnabled: true
        maskSource: labelMask
        visible: labelArt.status === Image.Ready
      }

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.accent
        visible: labelArt.status !== Image.Ready
      }

      Rectangle {
        anchors.centerIn: parent
        width: Theme.fs(3)
        height: width
        radius: width / 2
        color: "#111111"
      }
    }

    RotationAnimator on rotation {
      running: root.spinning && root.visible
      loops: Animation.Infinite
      from: 0
      to: 360
      duration: 4000
    }
  }

  Image {
    id: sleeve
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: root.sleeveSize
    height: root.sleeveSize
    source: root.source
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    smooth: true
    visible: false
  }

  Rectangle {
    id: sleeveMask
    anchors.fill: sleeve
    radius: Theme.fs(5)
    visible: false
    layer.enabled: true
  }

  MultiEffect {
    anchors.fill: sleeve
    source: sleeve
    maskEnabled: true
    maskSource: sleeveMask
    shadowEnabled: true
    shadowBlur: 0.6
    shadowOpacity: 0.6
    shadowHorizontalOffset: Theme.fs(2)
    visible: sleeve.status === Image.Ready
  }
}
