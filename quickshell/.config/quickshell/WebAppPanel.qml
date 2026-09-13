pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

// Web app manager (Super+Shift+A): install a website as a launcher, or remove
// one this tool installed.
//
// Same layer-shell shape as the other fullscreen overlays in this shell -- one
// instance per monitor, only the one matching panelScreen visible, exclusive
// keyboard focus, no space reserved.
//
// Two views on one `mode` property: the managed list, and the install form.
// Only apps with backend metadata are ever listed, so an unrelated .desktop file
// can never appear here.
PanelWindow {
  id: panel

  required property string ownerScreen

  visible: WebAppState.panelVisible
        && WebAppState.panelScreen === panel.ownerScreen

  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.namespace: "quickshell-webapps"

  property string mode: "list"     // "list" | "install"
  property bool shown: false

  readonly property int cardW: Math.min(Theme.webappCardW,
                                        panel.width - 2 * Theme.webappOuterMargin)
  readonly property int cardH: Math.min(Theme.webappCardH,
                                        panel.height - 2 * Theme.webappOuterMargin)

  // Super+Space opens the form before its URL has been read, so the address is
  // the field that still wants the user; Tab reaches the name from there.
  function focusInstallForm() {
    urlField.forceActiveFocus()
  }

  function dismiss() {
    if (WebAppState.confirmingId !== "") {
      WebAppState.cancelRemove()
      return
    }
    if (panel.mode === "install") {
      panel.mode = "list"
      return
    }
    WebAppState.close()
  }

  // ── scrim ──────────────────────────────────────────────────────────────────
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, Theme.webappScrimOpacity)
    opacity: panel.shown ? 1 : 0
    Behavior on opacity {
      NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
    }
    MouseArea {
      anchors.fill: parent
      onClicked: WebAppState.close()
    }
  }

  // ── card ───────────────────────────────────────────────────────────────────
  Rectangle {
    id: card
    anchors.centerIn: parent
    width: panel.cardW
    height: panel.cardH
    radius: Theme.radiusXL
    color: Theme.bg
    opacity: panel.shown ? 1 : 0
    border.width: Theme.borderWidth
    border.color: Qt.rgba(Theme.borderActive1.r, Theme.borderActive1.g,
                          Theme.borderActive1.b, 0.35)
    Behavior on opacity {
      NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
    }

    // Swallow clicks so they do not reach the dismissing scrim.
    MouseArea { anchors.fill: parent }

    Item {
      id: keys
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: panel.dismiss()

      // ── header ─────────────────────────────────────────────────────────────
      Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.webappPadding
        height: Theme.fs(24)

        Text {
          id: headerGlyph
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: WebAppState.glyphWeb
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.webappFontTitle
          color: Theme.accent
        }

        Text {
          anchors.left: headerGlyph.right
          anchors.leftMargin: Theme.gapS
          anchors.verticalCenter: parent.verticalCenter
          text: panel.mode === "install" ? "Install Web App" : "Web Apps"
          color: Theme.text
          font.family: Theme.uiFamily
          font.pixelSize: Theme.webappFontTitle
          font.bold: true
        }

        // Header action: add from the list, back from the form.
        Rectangle {
          id: headerBtn
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: headerBtnLabel.implicitWidth + Theme.gapL
          height: Theme.webappButtonH
          radius: Theme.radiusCell
          color: headerBtnMouse.containsMouse ? Theme.accent : Theme.surface

          Text {
            id: headerBtnLabel
            anchors.centerIn: parent
            text: panel.mode === "install" ? "Back" : "Install…"
            color: headerBtnMouse.containsMouse ? Theme.bgDeep : Theme.text
            font.family: Theme.uiFamily
            font.pixelSize: Theme.webappFontBody
          }

          MouseArea {
            id: headerBtnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (panel.mode === "install") {
                panel.mode = "list"
              } else {
                WebAppState.resetForm()
                panel.mode = "install"
                nameField.forceActiveFocus()
              }
            }
          }
        }
      }

      Rectangle {
        id: divider
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: Theme.gapM
        anchors.leftMargin: Theme.webappPadding
        anchors.rightMargin: Theme.webappPadding
        height: 1
        color: Theme.surface
      }

      // ══ LIST VIEW ═════════════════════════════════════════════════════════
      Item {
        visible: panel.mode === "list"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: divider.bottom
        anchors.bottom: parent.bottom
        anchors.margins: Theme.webappPadding

        Text {
          id: listStatus
          width: parent.width
          wrapMode: Text.WordWrap
          visible: text !== ""
          color: WebAppState.lastError !== "" ? Theme.error : Theme.textMuted
          font.family: Theme.uiFamily
          font.pixelSize: Theme.webappFontBody
          text: {
            if (WebAppState.lastError !== "")
              return WebAppState.lastError
            if (WebAppState.loading && WebAppState.apps.length === 0)
              return "Loading…"
            if (WebAppState.apps.length === 0)
              return "No web apps yet. Install… turns a website into a launcher "
                   + "you can find from the app menu."
            if (WebAppState.loadErrors.length > 0)
              return WebAppState.loadErrors.length
                   + " web app(s) could not be read and are not listed"
            return ""
          }
        }

        ListView {
          id: list
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: listStatus.visible ? listStatus.bottom : parent.top
          anchors.bottom: parent.bottom
          anchors.topMargin: listStatus.visible ? Theme.gapM : 0
          clip: true
          spacing: Theme.gapXS
          model: WebAppState.apps

          delegate: Rectangle {
            id: row
            required property var modelData

            width: list.width
            height: Theme.webappRowH
            radius: Theme.radiusM
            readonly property bool confirming:
              WebAppState.confirmingId === row.modelData.id
            color: row.confirming
              ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12)
              : (rowMouse.containsMouse ? Theme.surface : "transparent")
            border.width: Theme.borderWidth
            border.color: row.confirming
              ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.45)
              : "transparent"

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              // Below the trailing buttons so those still receive clicks.
              z: -1
            }

            // icon plate — Image over a glyph, cross-gated on load status, so a
            // missing or unreadable icon still shows something sensible.
            Rectangle {
              id: plate
              anchors.left: parent.left
              anchors.leftMargin: Theme.gapS
              anchors.verticalCenter: parent.verticalCenter
              width: Theme.webappIconPlate
              height: Theme.webappIconPlate
              radius: Theme.radiusS
              color: Theme.bgDeep
              clip: true

              Text {
                anchors.centerIn: parent
                visible: icon.status !== Image.Ready
                text: WebAppState.glyphWeb
                font.family: Theme.glyphFamily
                font.pixelSize: Theme.fs(18)
                color: Theme.textMuted
              }

              Image {
                id: icon
                anchors.fill: parent
                anchors.margins: Theme.fs(6)
                source: row.modelData.icon ? "file://" + row.modelData.icon : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                sourceSize.width: Theme.fs(96)
                sourceSize.height: Theme.fs(96)
                visible: status === Image.Ready
              }
            }

            Column {
              anchors.left: plate.right
              anchors.leftMargin: Theme.gapM
              anchors.right: actions.left
              anchors.rightMargin: Theme.gapS
              anchors.verticalCenter: parent.verticalCenter
              spacing: 1

              Text {
                width: parent.width
                text: row.confirming
                  ? "Remove " + row.modelData.name + "?"
                  : row.modelData.name
                color: row.confirming ? Theme.error : Theme.text
                font.family: Theme.uiFamily
                font.pixelSize: Theme.webappFontBody
                font.bold: row.confirming
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: row.confirming
                  ? "Removes the launcher, its metadata and its icon."
                  : row.modelData.host
                color: Theme.textMuted
                font.family: Theme.uiFamily
                font.pixelSize: Theme.webappFontSmall
                elide: Text.ElideRight
              }
            }

            // Two-step confirm in place of a modal: this shell has no
            // confirmation dialog anywhere, and a destructive one-click would be
            // the only unguarded delete of a thing the user created.
            Row {
              id: actions
              anchors.right: parent.right
              anchors.rightMargin: Theme.gapS
              anchors.verticalCenter: parent.verticalCenter
              spacing: Theme.gapXS

              Rectangle {
                visible: row.confirming
                width: cancelLabel.implicitWidth + Theme.gapM
                height: Theme.fs(26)
                radius: Theme.radiusCell
                color: Theme.surface
                Text {
                  id: cancelLabel
                  anchors.centerIn: parent
                  text: "Cancel"
                  color: Theme.text
                  font.family: Theme.uiFamily
                  font.pixelSize: Theme.webappFontSmall
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: WebAppState.cancelRemove()
                }
              }

              Rectangle {
                visible: row.confirming
                width: confirmLabel.implicitWidth + Theme.gapM
                height: Theme.fs(26)
                radius: Theme.radiusCell
                color: Theme.error
                Text {
                  id: confirmLabel
                  anchors.centerIn: parent
                  text: "Remove"
                  color: Theme.bgDeep
                  font.family: Theme.uiFamily
                  font.pixelSize: Theme.webappFontSmall
                  font.bold: true
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: WebAppState.remove(row.modelData.id)
                }
              }

              IconButton {
                visible: !row.confirming
                size: Theme.fs(26)
                glyphSize: Theme.fs(13)
                glyph: WebAppState.glyphDelete
                onClicked: WebAppState.askRemove(row.modelData.id)
              }
            }
          }
        }
      }

      // ══ INSTALL FORM ══════════════════════════════════════════════════════
      Column {
        visible: panel.mode === "install"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: divider.bottom
        anchors.margins: Theme.webappPadding
        spacing: Theme.gapM

        // --- name ---
        Text {
          text: "NAME"
          color: Theme.textDim
          font.family: Theme.uiFamily
          font.pixelSize: Theme.webappFontSmall
          font.bold: true
        }

        Rectangle {
          width: parent.width
          height: Theme.webappFieldH
          radius: Theme.radiusS
          color: Theme.bgDeep
          border.width: Theme.borderWidth
          border.color: nameField.activeFocus ? Theme.accent : Theme.surface

          TextInput {
            id: nameField
            anchors.fill: parent
            anchors.leftMargin: Theme.gapM
            anchors.rightMargin: Theme.gapM
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            font.family: Theme.uiFamily
            font.pixelSize: Theme.webappFontBody
            selectByMouse: true
            clip: true
            text: WebAppState.formName
            onTextChanged: WebAppState.formName = text
            KeyNavigation.tab: urlField

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: nameField.text === ""
              text: "YouTube"
              color: Theme.textMuted
              font.family: parent.font.family
              font.pixelSize: parent.font.pixelSize
            }
          }
        }

        // --- url ---
        Text {
          text: "URL"
          color: Theme.textDim
          font.family: Theme.uiFamily
          font.pixelSize: Theme.webappFontSmall
          font.bold: true
        }

        Rectangle {
          width: parent.width
          height: Theme.webappFieldH
          radius: Theme.radiusS
          color: Theme.bgDeep
          border.width: Theme.borderWidth
          border.color: urlField.activeFocus
            ? (WebAppState.formUrl === "" || WebAppState.urlValid
               ? Theme.accent : Theme.error)
            : Theme.surface

          TextInput {
            id: urlField
            anchors.fill: parent
            anchors.leftMargin: Theme.gapM
            anchors.rightMargin: Theme.gapM
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            font.family: Theme.uiFamily
            font.pixelSize: Theme.webappFontBody
            selectByMouse: true
            clip: true
            text: WebAppState.formUrl
            onTextChanged: WebAppState.urlEdited(text)
            KeyNavigation.tab: nameField
            onAccepted: if (WebAppState.canInstall) WebAppState.install()

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: urlField.text === ""
              text: "https://youtube.com/"
              color: Theme.textMuted
              font.family: parent.font.family
              font.pixelSize: parent.font.pixelSize
            }
          }
        }

        Text {
          visible: WebAppState.formUrl !== "" && !WebAppState.urlValid
          text: "Enter a valid http(s) website address"
          color: Theme.error
          font.family: Theme.uiFamily
          font.pixelSize: Theme.webappFontSmall
        }

        // --- icon ---
        Text {
          text: "ICON"
          color: Theme.textDim
          font.family: Theme.uiFamily
          font.pixelSize: Theme.webappFontSmall
          font.bold: true
        }

        Row {
          width: parent.width
          spacing: Theme.gapM

          // Doubles as a drop target: dragging an image here sets the icon.
          // There is no native file dialog on this desktop, so drag-and-drop and
          // the path field below are the two ways to pick one by hand.
          Rectangle {
            id: preview
            width: Theme.webappPreview
            height: Theme.webappPreview
            radius: Theme.radiusS
            color: Theme.bgDeep
            border.width: Theme.borderWidth
            border.color: drop.containsDrag ? Theme.accent : Theme.surface
            clip: true

            Text {
              anchors.centerIn: parent
              visible: previewImg.status !== Image.Ready
              text: WebAppState.iconState === "searching"
                ? "…" : WebAppState.glyphWeb
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(20)
              color: Theme.textMuted
            }

            Image {
              id: previewImg
              anchors.fill: parent
              anchors.margins: Theme.fs(8)
              source: WebAppState.iconPath ? "file://" + WebAppState.iconPath : ""
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              cache: false
              sourceSize.width: Theme.fs(128)
              sourceSize.height: Theme.fs(128)
              visible: status === Image.Ready
            }

            DropArea {
              id: drop
              anchors.fill: parent
              onDropped: drops => {
                if (drops.hasUrls && drops.urls.length > 0)
                  WebAppState.setIconPath(String(drops.urls[0]))
              }
            }
          }

          Column {
            width: parent.width - Theme.webappPreview - Theme.gapM
            spacing: Theme.gapXS

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: {
                switch (WebAppState.iconState) {
                case "searching": return "Finding icon…"
                case "found":     return "Icon found automatically"
                case "chosen":    return "Using the icon you picked"
                case "none":      return "No icon found — a letter tile will be used"
                default:          return "An icon is looked up once the URL is valid"
                }
              }
              color: WebAppState.iconState === "none"
                ? Theme.textDim : Theme.textMuted
              font.family: Theme.uiFamily
              font.pixelSize: Theme.webappFontSmall
            }

            Row {
              spacing: Theme.gapXS

              Rectangle {
                width: chooseLabel.implicitWidth + Theme.gapM
                height: Theme.fs(24)
                radius: Theme.radiusCell
                color: chooseMouse.containsMouse ? Theme.accent : Theme.surface
                Text {
                  id: chooseLabel
                  anchors.centerIn: parent
                  text: WebAppState.iconPathFieldVisible ? "Hide path" : "Choose icon…"
                  color: chooseMouse.containsMouse ? Theme.bgDeep : Theme.text
                  font.family: Theme.uiFamily
                  font.pixelSize: Theme.webappFontSmall
                }
                MouseArea {
                  id: chooseMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: WebAppState.iconPathFieldVisible =
                             !WebAppState.iconPathFieldVisible
                }
              }

              Rectangle {
                visible: WebAppState.iconState === "chosen"
                width: resetLabel.implicitWidth + Theme.gapM
                height: Theme.fs(24)
                radius: Theme.radiusCell
                color: Theme.surface
                Text {
                  id: resetLabel
                  anchors.centerIn: parent
                  text: "Auto"
                  color: Theme.text
                  font.family: Theme.uiFamily
                  font.pixelSize: Theme.webappFontSmall
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: WebAppState.clearChosenIcon()
                }
              }
            }
          }
        }

        // Revealed path field — the fallback for picking an icon by hand.
        Rectangle {
          visible: WebAppState.iconPathFieldVisible
          width: parent.width
          height: Theme.webappFieldH
          radius: Theme.radiusS
          color: Theme.bgDeep
          border.width: Theme.borderWidth
          border.color: Theme.surface

          TextInput {
            id: iconPathField
            anchors.fill: parent
            anchors.leftMargin: Theme.gapM
            anchors.rightMargin: Theme.gapM
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            font.family: Theme.uiFamily
            font.pixelSize: Theme.webappFontBody
            selectByMouse: true
            clip: true
            onAccepted: WebAppState.setIconPath(text)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: iconPathField.text === ""
              text: "or drag an image onto the preview — path, then Enter"
              color: Theme.textMuted
              font.family: parent.font.family
              font.pixelSize: parent.font.pixelSize
            }
          }
        }

        // --- backend error ---
        Text {
          visible: WebAppState.formError !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          maximumLineCount: 3
          elide: Text.ElideRight
          text: WebAppState.formError
          color: Theme.error
          font.family: Theme.uiFamily
          font.pixelSize: Theme.webappFontSmall
        }
      }

      // --- form actions, pinned to the bottom ---
      Row {
        visible: panel.mode === "install"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.webappPadding
        spacing: Theme.gapS

        Rectangle {
          width: cancelBtnLabel.implicitWidth + Theme.gapXL
          height: Theme.webappButtonH
          radius: Theme.radiusCell
          color: Theme.surface
          Text {
            id: cancelBtnLabel
            anchors.centerIn: parent
            text: "Cancel"
            color: Theme.text
            font.family: Theme.uiFamily
            font.pixelSize: Theme.webappFontBody
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { WebAppState.resetForm(); panel.mode = "list" }
          }
        }

        Rectangle {
          // Disabled until both fields validate, and while an install is in
          // flight, so a second click cannot start a duplicate.
          readonly property bool live: WebAppState.canInstall
          width: installBtnLabel.implicitWidth + Theme.gapXL
          height: Theme.webappButtonH
          radius: Theme.radiusCell
          color: live ? Theme.accent : Theme.surface
          opacity: live ? 1 : Theme.opacityDisabled

          Text {
            id: installBtnLabel
            anchors.centerIn: parent
            text: WebAppState.installing ? "Installing…" : "Install"
            color: parent.live ? Theme.bgDeep : Theme.textMuted
            font.family: Theme.uiFamily
            font.pixelSize: Theme.webappFontBody
            font.bold: true
          }

          MouseArea {
            anchors.fill: parent
            enabled: parent.live
            cursorShape: Qt.PointingHandCursor
            onClicked: WebAppState.install()
          }
        }
      }
    }
  }

  // ── lifecycle ──────────────────────────────────────────────────────────────

  Connections {
    target: WebAppState
    // Land back on the list after a successful install so the new app is visible.
    function onInstalled(name) { panel.mode = "list" }
    // Super+Space on a panel that is already open: onVisibleChanged will not
    // fire, so the requested view has to be applied directly.
    function onShowInstallForm() {
      if (!panel.visible)
        return
      panel.mode = "install"
      panel.focusInstallForm()
    }
  }

  onVisibleChanged: {
    if (!visible) {
      panel.shown = false
      WebAppState.cancelRemove()
      return
    }
    // "list" unless installCurrent() asked for the form. Consumed here so the
    // next plain Super+Alt+A opens on the list again.
    panel.mode = WebAppState.requestedMode
    WebAppState.requestedMode = "list"
    WebAppState.cancelRemove()
    keys.forceActiveFocus()
    if (panel.mode === "install")
      panel.focusInstallForm()
    panel.shown = true
  }
}
