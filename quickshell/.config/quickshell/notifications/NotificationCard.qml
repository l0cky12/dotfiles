import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."
import "NotificationLogic.js" as Logic

NotificationBorder {
  id: root

  property string app: ""
  property string appIcon: ""
  property string summary: ""
  property string body: ""
  property string image: ""
  property string actionsJson: "[]"
  readonly property var actionItems: {
    try { return JSON.parse(actionsJson) } catch (e) { return [] }
  }
  property string glyph: ""
  property int urgency: 1
  property real remainingFraction: 1
  property bool expiring: true

  readonly property bool hovered: hover.hovered
  readonly property bool singleLine: body.length === 0
  readonly property string iconValue: image.length > 0 ? image : appIcon
  readonly property string iconSource: resolveIcon(iconValue)
  readonly property bool compactGlyph: glyph.length > 0 && iconSource.length === 0 && singleLine
  readonly property bool hasLargeSlot: !compactGlyph && (iconSource.length > 0 || glyph.length > 0)
  // Spotify track cards: sleeve + spinning record, title pulled up out of the
  // body, and a live progress bar fed by MediaState instead of the plain icon.
  readonly property bool vinyl: Logic.isMediaNotification(app, iconSource)
  readonly property var bodyLines: body.split("\n")
  readonly property string trackTitle: vinyl ? bodyLines[0] : ""
  readonly property string trackDetail: vinyl ? bodyLines.slice(1).join(" ") : ""
  readonly property int verticalPadding: Theme.fs(singleLine
    ? NotificationConfig.singleLinePadding : NotificationConfig.multiLinePadding)

  signal closeRequested()
  signal cardClicked()
  signal actionRequested(string identifier)

  function resolveIcon(value) {
    const icon = String(value || "")
    if (!icon) return ""
    if (icon.indexOf("file://") === 0 || icon.indexOf("image://") === 0) return icon
    if (icon.charAt(0) === "/") return "file://" + icon
    return Quickshell.iconPath(icon, true)
  }

  implicitWidth: Theme.fs(NotificationConfig.cardWidth)
  implicitHeight: row.implicitHeight + root.verticalPadding * 2 + topWidth + bottomWidth
                  + (buttons.visible ? buttons.implicitHeight + Theme.fs(8) : 0)
  cornerRadius: Theme.notificationRadius

  HoverHandler { id: hover }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.closeRequested()
      else root.cardClicked()
    }
  }

  RowLayout {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: Theme.fs(NotificationConfig.sidePadding)
    anchors.rightMargin: Theme.fs(NotificationConfig.sidePadding)
    anchors.topMargin: root.verticalPadding
    spacing: root.compactGlyph ? Theme.fs(NotificationConfig.glyphGap)
                               : Theme.fs(NotificationConfig.iconGap)

    NotificationVinyl {
      visible: root.vinyl
      Layout.preferredWidth: visible ? implicitWidth : 0
      Layout.preferredHeight: visible ? implicitHeight : 0
      Layout.alignment: Qt.AlignVCenter
      source: root.iconSource
      sleeveSize: Theme.fs(NotificationConfig.vinylSize)
    }

    Item {
      Layout.preferredWidth: visible ? Theme.fs(NotificationConfig.iconSize) : 0
      Layout.preferredHeight: visible ? Theme.fs(NotificationConfig.iconSize) : 0
      Layout.alignment: Qt.AlignVCenter
      visible: !root.vinyl && root.hasLargeSlot && (root.glyph.length > 0 || icon.status !== Image.Error)

      Image {
        id: icon
        anchors.fill: parent
        source: root.iconSource
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        visible: status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        visible: root.glyph.length > 0 && icon.status !== Image.Ready
        text: root.glyph
        color: Theme.notificationText
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(24)
      }
    }

    Text {
      visible: root.compactGlyph
      Layout.alignment: Qt.AlignVCenter
      text: root.glyph
      color: Theme.notificationText
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(18)
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      Layout.rightMargin: Theme.fs(10)
      spacing: Theme.fs(2)

      Text {
        Layout.fillWidth: true
        visible: root.summary.length > 0
        text: root.vinyl ? root.summary.toUpperCase() : root.summary
        textFormat: Text.PlainText
        color: root.vinyl ? Theme.notificationCountdown : Theme.notificationText
        font.family: Theme.uiFamily
        font.pixelSize: Theme.fs(root.vinyl ? 10 : 14)
        font.weight: root.vinyl ? Font.Bold : Font.DemiBold
        font.letterSpacing: root.vinyl ? Theme.fs(1.6) : 0
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: root.vinyl ? 1 : 2
      }

      Text {
        Layout.fillWidth: true
        visible: root.vinyl && root.trackTitle.length > 0
        text: root.trackTitle
        textFormat: Text.PlainText
        color: Theme.notificationText
        font.family: Theme.uiFamily
        font.pixelSize: Theme.fs(17)
        font.weight: Font.Bold
        elide: Text.ElideRight
        maximumLineCount: 1
      }

      Text {
        Layout.fillWidth: true
        visible: root.body.length > 0
        text: root.vinyl ? root.trackDetail : root.body
        textFormat: Text.PlainText
        color: Theme.notificationBodyText
        font.family: Theme.uiFamily
        font.pixelSize: Theme.fs(14)
        wrapMode: root.vinyl ? Text.NoWrap : Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: root.vinyl ? 1 : 3
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Theme.fs(6)
        visible: root.vinyl && MediaState.hasTrack
        height: Theme.fs(3)
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.12)

        Rectangle {
          width: parent.width * MediaState.progress
          height: parent.height
          radius: parent.radius
          color: Theme.notificationCountdown
          Behavior on width { NumberAnimation { duration: 250 } }
        }
      }
    }
  }

  RowLayout {
    id: buttons
    anchors.top: row.bottom
    anchors.topMargin: Theme.fs(8)
    anchors.left: row.left
    anchors.right: row.right
    spacing: Theme.fs(8)
    visible: root.actionItems.length > 0

    Repeater {
      model: root.actionItems
      delegate: Button {
        required property var modelData
        objectName: "notificationAction-" + modelData.identifier
        Layout.fillWidth: true
        text: modelData.text
        implicitHeight: Theme.fs(30)
        onClicked: root.actionRequested(modelData.identifier)
        contentItem: Text {
          text: parent.text
          textFormat: Text.PlainText
          color: Theme.notificationText
          font.family: Theme.uiFamily
          font.pixelSize: Theme.fs(14)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }
        background: Rectangle {
          radius: Theme.fs(4)
          color: parent.hovered || parent.activeFocus ? Theme.notificationBorder1 : Theme.notificationBackground
          border.color: Theme.notificationBorder1
        }
      }
    }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.leftWidth
    anchors.bottomMargin: root.bottomWidth
    width: Math.max(0, (parent.width - root.leftWidth - root.rightWidth) *
                           Math.max(0, Math.min(1, root.remainingFraction)))
    height: Theme.fs(NotificationConfig.countdownHeight)
    visible: root.expiring
    color: root.urgency === 2 ? Theme.critical : Theme.notificationCountdown
  }

  Item {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: root.topWidth + Theme.fs(3)
    anchors.rightMargin: root.rightWidth + Theme.fs(3)
    width: Theme.fs(NotificationConfig.closeSize)
    height: Theme.fs(NotificationConfig.closeSize)
    visible: opacity > 0
    opacity: root.hovered ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: NotificationConfig.closeFadeMs } }

    Text {
      anchors.centerIn: parent
      text: "×"
      color: closeArea.containsMouse ? Theme.notificationText : Theme.notificationClose
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(16)
    }

    MouseArea {
      id: closeArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.closeRequested()
    }
  }
}
