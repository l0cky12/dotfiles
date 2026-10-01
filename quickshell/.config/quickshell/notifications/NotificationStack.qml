import QtQuick
import ".."

Item {
  id: root
  required property string ownerScreen
  property alias inputItem: column

  implicitWidth: column.implicitWidth
  implicitHeight: column.implicitHeight

  Column {
    id: column
    spacing: Theme.fs(NotificationConfig.stackGap)

    Repeater {
      model: NotificationService.popupModel

      delegate: Item {
        id: slot
        required property string key
        required property string app
        required property string desktopEntry
        required property string appIcon
        required property string summary
        required property string body
        required property string image
        required property string actionsJson
        required property string glyph
        required property int urgency
        required property real expireTimeout
        required property real timestamp
        required property string screenName
        required property real deadline
        required property bool replay
        required property bool restored
        required property bool closing
        required property string closeReason

        readonly property bool belongsHere: NotificationService.screenFor(screenName) === root.ownerScreen
        readonly property real lifetime: NotificationService.durationFor(urgency, expireTimeout)
        property real remainingMs: lifetime
        property real lastTick: Date.now()

        visible: belongsHere
        width: visible ? card.implicitWidth : 0
        height: visible ? card.implicitHeight : 0
        opacity: closing ? 0 : 1
        x: closing ? Theme.fs(24) : 0

        Behavior on x { NumberAnimation { duration: NotificationConfig.animationMs } }
        Behavior on opacity { NumberAnimation { duration: NotificationConfig.animationMs } }
        Behavior on y { NumberAnimation { duration: NotificationConfig.animationMs } }

        function resetLifetime() {
          const now = Date.now()
          remainingMs = lifetime <= 0 ? 0 : (deadline > 0 ? Math.max(0, deadline - now) : lifetime)
          lastTick = now
        }

        Component.onCompleted: resetLifetime()
        onDeadlineChanged: resetLifetime()

        Timer {
          interval: 50
          repeat: true
          running: slot.belongsHere && slot.lifetime > 0 && !card.hovered && !slot.closing
          onRunningChanged: slot.lastTick = Date.now()
          onTriggered: {
            const now = Date.now()
            slot.remainingMs -= Math.max(0, now - slot.lastTick)
            slot.lastTick = now
            if (slot.remainingMs <= 0) {
              slot.remainingMs = 0
              NotificationService.expireKey(slot.key)
            }
          }
        }

        Timer {
          interval: NotificationConfig.animationMs
          running: slot.closing && NotificationConfig.animationMs > 0
          onTriggered: NotificationService.finalizeClose(slot.key)
        }

        NotificationCard {
          id: card
          anchors.right: parent.right
          app: slot.app
          appIcon: slot.appIcon
          summary: slot.summary
          body: slot.body
          image: slot.image
          actionsJson: slot.actionsJson
          glyph: slot.glyph
          urgency: slot.urgency
          expiring: slot.lifetime > 0
          remainingFraction: slot.lifetime > 0 ? slot.remainingMs / slot.lifetime : 1
          onCloseRequested: NotificationService.dismissKey(slot.key)
          onCardClicked: NotificationService.invokeKey(slot.key)
          onActionRequested: function(identifier) { NotificationService.invokeKey(slot.key, identifier) }
        }
      }
    }
  }
}
