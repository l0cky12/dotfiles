import Quickshell
import QtQuick

// Construct an invisible panel with fixture rows. No layer surface is mapped.
Scope {
  id: smoke
  QtObject {
    id: fixtureController
    property bool panelVisible: false
    property string panelScreen: "smoke"
    property var directRows: []
    property var filtered: directRows
    property int selectedIndex: 0
    property string title: "Fixture"
    property string query: ""
    property string lastError: ""
    property bool loaded: true
    signal queryReset()
    function display(row) { return row.label }
  }
  LmenuPanel {
    id: panel
    ownerScreen: "smoke"
    controller: fixtureController
    implicitHeight: 800
  }
  Component.onCompleted: {
    const rows = []
    for (let i = 0; i < 500; i++)
      rows.push({ label: "App " + i, disabled: false })
    fixtureController.directRows = rows
    Qt.callLater(function() {
      if (panel.visible || panel.shownRows <= 0 || panel.shownRows >= rows.length
          || panel.listHeight > panel.height) {
        console.log("FAIL: large lmenu list does not fit the viewport")
      } else {
        console.log("ok: lmenu panel compiles")
        console.log("ok: 500-row lmenu is bounded to " + panel.shownRows + " visible rows")
      }
      Qt.quit()
    })
  }
}
