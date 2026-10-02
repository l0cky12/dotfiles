import Quickshell
import QtQuick
import "notifications" as Notifications

// Headless parse/instantiation harness used by the validation instructions in
// README.md. It deliberately omits layer-shell window construction.
Scope {
  id: smoke
  readonly property var service: Notifications.NotificationService
  property Component borderType: Component { Notifications.NotificationBorder {} }
  property Component cardType: Component { Notifications.NotificationCard {} }
  property Component stackType: Component {
    Notifications.NotificationStack { ownerScreen: "smoke" }
  }
  Timer {
    interval: 250
    running: true
    onTriggered: {
      const card = cardType.createObject(null, {
        summary: "Screenshot ready", body: "Copied to clipboard",
        actionsJson: JSON.stringify([
          {identifier: "edit", text: "Edit"}, {identifier: "save", text: "Save"}
        ])
      })
      if (!card) { console.log("FAIL: screenshot action card could not be created"); Qt.quit(); return }
      const edit = smoke.find(card, "notificationAction-edit")
      const save = smoke.find(card, "notificationAction-save")
      if (!edit || !save || !edit.visible || !save.visible || edit.mapToItem(card, 0, 0).y <= 0)
        console.log("FAIL: Edit and Save buttons are missing below the notification")
      else {
        if (save.mapToItem(card, 0, save.height).y >= card.height)
          console.log("FAIL: notification clips its action buttons")
        let chosen = ""
        card.actionRequested.connect(function(identifier) { chosen = identifier })
        edit.clicked()
        if (chosen !== "edit") console.log("FAIL: Edit button did not request edit")
        save.clicked()
        if (chosen !== "save") console.log("FAIL: Save button did not request save")
        let invoked = ""
        const key = "1234-7"
        service.insertEntry({key: key, summary: "Fixture"}, true)
        service.liveRefs[key] = {actions: [
          {identifier: "save", invoke: function() { invoked = "save" }}
        ]}
        if (service.invokeKey(key, "save") !== "invoked" || invoked !== "save")
          console.log("FAIL: notification service did not invoke the selected action")
        else console.log("ok: notification action rendering and invocation")
        const restored = service.normalizedEntry({restored: true, actionsJson: card.actionsJson})
        if (restored.actionsJson !== "[]") console.log("FAIL: restored notification exposes expired actions")
      }
      card.destroy()
      Qt.quit()
    }
  }

  function find(item, name) {
    if (item.objectName === name) return item
    for (let i = 0; i < item.children.length; i++) {
      const match = find(item.children[i], name)
      if (match) return match
    }
    return null
  }
}
