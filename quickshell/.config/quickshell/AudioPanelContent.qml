import QtQuick

// The visual body is separate from PopupWindow so fixture tests can render
// the real rows without requiring a running Wayland compositor.
Item {
  id: root
  required property var audio

  implicitWidth: Theme.fs(380)
  implicitHeight: content.implicitHeight

  readonly property int outputCount: audio.sinks ? audio.sinks.length : 0
  readonly property int inputCount: audio.sources ? audio.sources.length : 0
  readonly property int streamCount: audio.streams ? audio.streams.length : 0
  readonly property bool hasDevices: outputCount > 0 || inputCount > 0
  readonly property bool isEmpty: !hasDevices && streamCount === 0

  Column {
    id: content
    width: parent.width
    spacing: Theme.gapM

    Item {
      width: parent.width
      height: Theme.fs(34)

      Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.gapS

        Text {
          text: root.audio.glyph
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(20)
          color: Theme.text
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          spacing: Theme.fs(2)
          anchors.verticalCenter: parent.verticalCenter
          Text {
            text: "Audio"
            color: Theme.text
            font.bold: true
            font.pixelSize: Theme.fs(15)
          }
          Text {
            text: !root.audio.available ? "PipeWire unavailable"
              : root.audio.muted ? "Muted"
              : root.audio.sink ? root.audio.volumePct + "%" : "No output"
            color: Theme.textDim
            font.pixelSize: Theme.fs(11)
          }
        }
      }

      IconButton {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        glyph: root.audio.muted
          ? String.fromCodePoint(0xf0581) : String.fromCodePoint(0xf057e)
        active: root.audio.muted
        enabled: !!(root.audio.sink && root.audio.sink.audio)
        onClicked: root.audio.toggleMute()
      }
    }

    Card {
      width: parent.width
      height: Theme.fs(72)
      title: "MASTER OUTPUT"
      unavailable: !(root.audio.sink && root.audio.sink.audio)
      unavailableText: root.audio.available ? "No output device" : "Audio unavailable"

      Item {
        anchors.fill: parent

        VolumeSlider {
          anchors.left: parent.left
          anchors.right: level.left
          anchors.rightMargin: Theme.gapS
          anchors.verticalCenter: parent.verticalCenter
          value: root.audio.sink && root.audio.sink.audio
            ? root.audio.sink.audio.volume : 0
          onMoved: fraction => root.audio.setVolume(fraction)
        }

        Text {
          id: level
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.audio.volumePct + "%"
          color: Theme.text
          font.pixelSize: Theme.fs(11)
        }
      }
    }

    Column {
      visible: root.hasDevices
      width: parent.width
      height: visible ? implicitHeight : 0
      spacing: Theme.gapS

      Text {
        text: "Devices"
        color: Theme.text
        font.bold: true
        font.pixelSize: Theme.fs(13)
      }

      Column {
        id: outputDevices
        objectName: "audio-output-list"
        visible: root.outputCount > 0
        width: parent.width
        height: visible ? implicitHeight : 0
        spacing: Theme.gapXS

        Text {
          text: "OUTPUT"
          color: Theme.textMuted
          font.bold: true
          font.pixelSize: Theme.fs(10)
        }

        Repeater {
          model: root.audio.sinks || []

          delegate: Rectangle {
            id: outputRow
            required property var modelData
            required property int index
            objectName: "audio-output-row-" + index
            readonly property bool activeDevice: root.audio.sink === modelData
            readonly property string deviceTitle: root.audio.deviceDescription(modelData)
            readonly property var ports: root.audio.devicePorts(modelData)
            width: outputDevices.width
            height: details.implicitHeight + Theme.gapS * 2
            radius: Theme.radiusCell
            color: activeDevice ? Theme.selection : Theme.surface
            border.width: Theme.borderWidth
            border.color: activeDevice ? Theme.borderActive1 : Theme.hairline

            Column {
              id: details
              anchors.left: parent.left
              anchors.right: activeMark.left
              anchors.leftMargin: Theme.gapS
              anchors.rightMargin: Theme.gapS
              anchors.verticalCenter: parent.verticalCenter
              spacing: Theme.fs(2)

              Text {
                width: parent.width
                text: outputRow.deviceTitle
                color: Theme.text
                font.pixelSize: Theme.fs(11)
                font.bold: outputRow.activeDevice
                elide: Text.ElideRight
              }
              Text {
                visible: text !== ""
                width: parent.width
                text: root.audio.deviceName(modelData)
                color: Theme.textMuted
                font.pixelSize: Theme.fs(9)
                elide: Text.ElideRight
              }
              Text {
                visible: outputRow.ports.length > 0
                width: parent.width
                text: "Port: " + outputRow.ports.join(" · ")
                color: Theme.textDim
                font.pixelSize: Theme.fs(9)
                elide: Text.ElideRight
              }
            }

            Text {
              id: activeMark
              anchors.right: parent.right
              anchors.rightMargin: Theme.gapS
              anchors.verticalCenter: parent.verticalCenter
              text: String.fromCodePoint(0xf012c)
              visible: outputRow.activeDevice
              color: Theme.accent
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(14)
            }

            MouseArea {
              anchors.fill: parent
              onClicked: root.audio.setSink(modelData)
            }
          }
        }
      }

      Column {
        id: inputDevices
        objectName: "audio-input-list"
        visible: root.inputCount > 0
        width: parent.width
        height: visible ? implicitHeight : 0
        spacing: Theme.gapXS

        Text {
          text: "INPUT"
          color: Theme.textMuted
          font.bold: true
          font.pixelSize: Theme.fs(10)
        }

        Repeater {
          model: root.audio.sources || []

          delegate: Rectangle {
            id: inputRow
            required property var modelData
            required property int index
            objectName: "audio-input-row-" + index
            readonly property bool activeDevice: root.audio.source === modelData
            readonly property string deviceTitle: root.audio.deviceDescription(modelData)
            readonly property var ports: root.audio.devicePorts(modelData)
            width: inputDevices.width
            height: inputDetails.implicitHeight + Theme.gapS * 2
            radius: Theme.radiusCell
            color: activeDevice ? Theme.selection : Theme.surface
            border.width: Theme.borderWidth
            border.color: activeDevice ? Theme.borderActive1 : Theme.hairline

            Column {
              id: inputDetails
              anchors.left: parent.left
              anchors.right: inputControls.left
              anchors.leftMargin: Theme.gapS
              anchors.rightMargin: Theme.gapS
              anchors.verticalCenter: parent.verticalCenter
              spacing: Theme.fs(2)

              Text {
                width: parent.width
                text: inputRow.deviceTitle
                color: Theme.text
                font.pixelSize: Theme.fs(11)
                font.bold: inputRow.activeDevice
                elide: Text.ElideRight
              }
              Text {
                visible: text !== ""
                width: parent.width
                text: root.audio.deviceName(modelData)
                color: Theme.textMuted
                font.pixelSize: Theme.fs(9)
                elide: Text.ElideRight
              }
              Text {
                visible: inputRow.ports.length > 0
                width: parent.width
                text: "Port: " + inputRow.ports.join(" · ")
                color: Theme.textDim
                font.pixelSize: Theme.fs(9)
                elide: Text.ElideRight
              }
            }

            Row {
              id: inputControls
              anchors.right: parent.right
              anchors.rightMargin: Theme.gapS
              anchors.verticalCenter: parent.verticalCenter
              spacing: Theme.gapXS

              Text {
                visible: inputRow.activeDevice
                text: root.audio.inputVolumePct + "%"
                color: Theme.textDim
                font.pixelSize: Theme.fs(9)
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                visible: inputRow.activeDevice
                text: String.fromCodePoint(0xf012c)
                color: Theme.accent
                font.family: Theme.glyphFamily
                font.pixelSize: Theme.fs(14)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              anchors.fill: parent
              onClicked: root.audio.setSource(modelData)
            }
          }
        }

        VolumeSlider {
          visible: !!(root.audio.source && root.audio.source.audio)
          width: parent.width
          value: root.audio.source && root.audio.source.audio
            ? root.audio.source.audio.volume : 0
          onMoved: fraction => root.audio.setInputVolume(fraction)
        }
      }
    }

    Column {
      id: applications
      objectName: "audio-application-list"
      visible: root.streamCount > 0
      width: parent.width
      height: visible ? implicitHeight : 0
      spacing: Theme.gapS

      Text {
        text: "Applications"
        color: Theme.text
        font.bold: true
        font.pixelSize: Theme.fs(13)
      }

      Repeater {
        model: root.audio.streams || []

        delegate: Card {
          id: streamRow
          required property var modelData
          required property int index
          objectName: "audio-stream-row-" + index
          readonly property bool streamMuted: !!(modelData.audio && modelData.audio.muted)
          readonly property string applicationTitle: root.audio.streamLabel(modelData)
          width: applications.width
          height: Theme.fs(68)
          padding: Theme.gapS

          Row {
            anchors.fill: parent
            spacing: Theme.gapS

            Item {
              width: Theme.fs(30)
              height: width
              anchors.verticalCenter: parent.verticalCenter

              Image {
                id: appIcon
                anchors.fill: parent
                source: root.audio.streamIcon(modelData)
                sourceSize.width: width
                sourceSize.height: height
                fillMode: Image.PreserveAspectFit
              }
              Text {
                anchors.centerIn: parent
                visible: appIcon.status !== Image.Ready
                text: String.fromCodePoint(0xf087b)
                color: Theme.textDim
                font.family: Theme.glyphFamily
                font.pixelSize: Theme.fs(17)
              }
            }

            Column {
              width: parent.width - Theme.fs(30) - muteButton.width - Theme.gapS * 2
              spacing: Theme.fs(4)
              anchors.verticalCenter: parent.verticalCenter

              Item {
                width: parent.width
                height: Theme.fs(14)
                Text {
                  anchors.left: parent.left
                  anchors.right: percent.left
                  anchors.rightMargin: Theme.gapS
                  text: streamRow.applicationTitle
                  color: Theme.text
                  font.pixelSize: Theme.fs(11)
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  id: percent
                  anchors.right: parent.right
                  text: root.audio.streamVolumePct(modelData) + "%"
                  color: Theme.textDim
                  font.pixelSize: Theme.fs(10)
                }
              }

              VolumeSlider {
                width: parent.width
                value: modelData.audio ? modelData.audio.volume : 0
                fillColor: streamRow.streamMuted ? Theme.textMuted : Theme.accent
                onMoved: fraction => root.audio.setStreamVolume(modelData, fraction)
              }
            }

            IconButton {
              id: muteButton
              anchors.verticalCenter: parent.verticalCenter
              glyph: streamRow.streamMuted
                ? String.fromCodePoint(0xf0581) : String.fromCodePoint(0xf057e)
              active: streamRow.streamMuted
              onClicked: root.audio.toggleStreamMute(modelData)
            }
          }
        }
      }
    }

    Card {
      objectName: "audio-empty-state"
      visible: root.isEmpty
      width: parent.width
      height: visible ? Theme.fs(76) : 0
      unavailable: true
      unavailableText: root.audio.available
        ? "No audio devices or playback streams" : "PipeWire unavailable"
    }
  }
}
