import QtQuick
import Quickshell

// The compact, themed control surface for NetworkState.  It deliberately
// keeps the password flow out of QML: secured networks launch nmtui and QR
// generation receives only safe metadata back from the backend.
PopupWindow {
  id: panel
  required property Item anchorItem
  required property string ownerScreen
  visible: NetworkState.panelVisible && NetworkState.panelScreen === ownerScreen
  grabFocus: true
  anchor.item: anchorItem
  anchor.edges: Edges.Bottom
  anchor.gravity: Edges.Bottom
  anchor.margins.top: Theme.gapS
  implicitWidth: Theme.fs(520)
  // Fit the content instead of always reserving the tallest case: the drawer
  // is short when Advanced IPv4 is collapsed and only grows to maxHeight,
  // beyond which the network list scrolls rather than running off screen.
  readonly property int maxHeight: Theme.fs(680)
  implicitHeight: Math.min(maxHeight,
    header.implicitHeight + Theme.gapM + content.implicitHeight + Theme.gapL * 2)

  property bool advancedOpen: false
  // "Share Wi-Fi" no longer swaps this drawer into a QR view: a QR in a
  // bar-anchored popup lands top-right, so it lives in WifiQrOverlay, a
  // dedicated screen-centred window. qrResult being set opens that
  // overlay directly; this panel keeps its normal behaviour underneath.
  property bool confirmVisible: false
  property string confirmTitle: ""
  property string confirmDetail: ""
  property var confirmAction: null
  property string manualAddressText: ""
  property string manualPrefixText: ""
  property string manualGatewayText: ""
  property string manualDnsText: ""
  function confirm(title, detail, action) {
    confirmTitle = title; confirmDetail = detail; confirmAction = action; confirmVisible = true
  }

  Rectangle {
    anchors.fill: parent; color: Theme.bg
    FocusScope {
      id: keys; anchors.fill: parent; focus: true
      Keys.onEscapePressed: {
        if (panel.confirmVisible) panel.confirmVisible = false
        else NetworkState.panelVisible = false
      }

      Item {
        visible: true
        anchors.fill: parent
        anchors.margins: Theme.gapL
        Column {
          id: header; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
          spacing: Theme.gapS
          Row {
            width: parent.width; spacing: Theme.gapS
            Text {
              text: NetworkState.connType === "ethernet" ? String.fromCodePoint(0xef44) : String.fromCodePoint(0xf0928)
              color: NetworkState.connType === "none" ? Theme.textMuted : Theme.accent
              font.family: Theme.glyphFamily; font.pixelSize: Theme.fs(24)
            }
            Column {
              width: parent.width - Theme.fs(130); spacing: Theme.fs(2)
              Text { text: NetworkState.connType === "wifi" ? (NetworkState.ssid || "Wi-Fi") : NetworkState.connType === "ethernet" ? "Ethernet" : "Network"; color: Theme.text; font.pixelSize: Theme.fs(16); font.bold: true }
              Text { text: NetworkState.loading ? "Refreshing…" : NetworkState.connectionState + (NetworkState.iface ? " • " + NetworkState.iface : ""); color: Theme.textDim; font.pixelSize: Theme.fs(11) }
            }
            Rectangle {
              width: Theme.fs(82); height: Theme.fs(28); radius: Theme.radiusCell
              color: NetworkState.wifiEnabled ? Theme.accent : Theme.surface
              Text { anchors.centerIn: parent; text: NetworkState.wifiEnabled ? "Wi-Fi on" : "Wi-Fi off"; color: NetworkState.wifiEnabled ? Theme.bgDeep : Theme.text; font.pixelSize: Theme.fs(10); font.bold: true }
              MouseArea { anchors.fill: parent; onClicked: NetworkState.setWifi(!NetworkState.wifiEnabled) }
            }
          }
          Rectangle { width: parent.width; height: 1; color: Theme.surface }
        }

        Flickable {
          anchors.left: parent.left; anchors.right: parent.right; anchors.top: header.bottom; anchors.bottom: parent.bottom
          anchors.topMargin: Theme.gapM; clip: true; contentWidth: width; contentHeight: content.implicitHeight
          Column {
            id: content; width: parent.width; spacing: Theme.gapM
            Grid {
              width: parent.width; columns: 3; columnSpacing: Theme.gapM; rowSpacing: Theme.gapS
              Repeater {
                model: [
                  {label:"Signal", value: NetworkState.connType === "wifi" ? NetworkState.signalPct + "%" : "-"},
                  {label:"IPv4", value: NetworkState.ipAddress},
                  {label:"Gateway", value: NetworkState.gateway},
                  {label:"DNS", value: NetworkState.dnsServers.length ? NetworkState.dnsServers.join(" ") : "Automatic"},
                  {label:"IPv4 mode", value: NetworkState.ipv4Method || "-"},
                  {label:"Profile", value: NetworkState.profile || "-"}
                ]
                Column {
                  required property var modelData; width: (content.width - Theme.gapM * 2) / 3; spacing: Theme.fs(2)
                  Text { text: parent.modelData.label; color: Theme.textMuted; font.pixelSize: Theme.fs(10) }
                  Text { text: parent.modelData.value; color: Theme.text; font.pixelSize: Theme.fs(11); elide: Text.ElideRight; width: parent.width }
                }
              }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.surface }
            Row {
              width: parent.width; spacing: Theme.gapS
              Text { text: "Wi-Fi networks"; color: Theme.text; font.bold: true; font.pixelSize: Theme.fs(13); width: parent.width - Theme.fs(100) }
              Rectangle {
                width: Theme.fs(92); height: Theme.fs(26); radius: Theme.radiusCell
                color: scanArea.containsMouse ? Theme.surfaceAlt : Theme.surface; opacity: NetworkState.wifiEnabled ? 1 : Theme.opacityDisabled
                Text { anchors.centerIn: parent; text: NetworkState.scanning ? "Scanning…" : "Scan"; color: Theme.text; font.pixelSize: Theme.fs(10) }
                MouseArea { id: scanArea; anchors.fill: parent; hoverEnabled: true; enabled: NetworkState.wifiEnabled && !NetworkState.scanning; onClicked: NetworkState.scan() }
              }
            }
            Text { visible: !NetworkState.wifiEnabled; text: "Turn Wi-Fi on to scan and connect."; color: Theme.textMuted; font.pixelSize: Theme.fs(11) }
            ListView {
              visible: NetworkState.wifiEnabled; width: parent.width; height: Math.min(Theme.fs(156), contentHeight); clip: true
              model: NetworkState.wifiNetworks; spacing: Theme.fs(4)
              delegate: Rectangle {
                required property var modelData; width: ListView.view.width; height: Theme.fs(36); radius: Theme.radiusCell; color: Theme.surface
                Row { anchors.fill: parent; anchors.margins: Theme.fs(8); spacing: Theme.gapS
                  Text { text: String.fromCodePoint(0xf0928); font.family: Theme.glyphFamily; color: Theme.accent; font.pixelSize: Theme.fs(14) }
                  Text { text: modelData.ssid; color: Theme.text; width: parent.width - Theme.fs(190); elide: Text.ElideRight; font.pixelSize: Theme.fs(11) }
                  Text { text: modelData.signal + "%"; color: Theme.textDim; width: Theme.fs(34); font.pixelSize: Theme.fs(10) }
                  Rectangle { width: Theme.fs(76); height: Theme.fs(20); radius: Theme.radiusCell; color: Theme.surfaceAlt
                    Text { anchors.centerIn: parent; text: modelData.security === "--" || modelData.security === "" ? "Connect" : "Connect…"; color: Theme.text; font.pixelSize: Theme.fs(9) }
                    MouseArea { anchors.fill: parent; onClicked: (modelData.security === "--" || modelData.security === "") ? NetworkState.connectOpen(modelData.bssid) : NetworkState.connectSecure() }
                  }
                }
              }
            }
            Row { visible: NetworkState.connectionState === "connected"; spacing: Theme.gapS
              Rectangle { width: Theme.fs(112); height: Theme.fs(28); radius: Theme.radiusCell; color: Theme.surface
                Text { anchors.centerIn: parent; text: "Disconnect"; color: Theme.text; font.pixelSize: Theme.fs(10) }
                MouseArea { anchors.fill: parent; onClicked: panel.confirm("Disconnect", "This disconnects " + (NetworkState.ssid || NetworkState.iface) + ".", function() { NetworkState.disconnect() }) }
              }
              Rectangle { width: Theme.fs(112); height: Theme.fs(28); radius: Theme.radiusCell; color: Theme.surface
                Text { anchors.centerIn: parent; text: NetworkState.speedTestRunning ? "Testing…" : "Speed test"; color: Theme.text; font.pixelSize: Theme.fs(10) }
                MouseArea { anchors.fill: parent; enabled: !NetworkState.speedTestRunning; onClicked: NetworkState.runSpeedTest(panel.ownerScreen) }
              }
              Rectangle { visible: NetworkState.connType === "wifi"; width: Theme.fs(112); height: Theme.fs(28); radius: Theme.radiusCell; color: Theme.accent
                Text { anchors.centerIn: parent; text: NetworkState.qrLoading ? "Creating…" : "Share Wi-Fi"; color: Theme.bgDeep; font.pixelSize: Theme.fs(10); font.bold: true }
                MouseArea { anchors.fill: parent; enabled: !NetworkState.qrLoading; onClicked: NetworkState.shareWifi() }
              }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.surface }
            Text { text: "DNS"; color: Theme.text; font.bold: true; font.pixelSize: Theme.fs(13) }
            Row { spacing: Theme.fs(5)
              Repeater { model: NetworkState.dnsProviders
                Rectangle { required property var modelData; width: Theme.fs(88); height: Theme.fs(26); radius: Theme.radiusCell; color: Theme.surface
                  Text { anchors.centerIn: parent; text: modelData.label; color: Theme.text; font.pixelSize: Theme.fs(9) }
                  MouseArea { anchors.fill: parent; onClicked: panel.confirm("Apply DNS", modelData.id === "automatic" ? "Restore DNS supplied by DHCP?" : "Use " + modelData.label + " DNS. This may reconnect the network.", function() { NetworkState.applyDns(modelData.values) }) }
                }
              }
            }
            Row { spacing: Theme.gapS
              Rectangle { width: Theme.fs(230); height: Theme.fs(28); radius: Theme.radiusCell; color: Theme.bgDeep; border.color: Theme.surface
                TextInput { id: customDns; anchors.fill: parent; anchors.leftMargin: Theme.gapS; anchors.rightMargin: Theme.gapS; verticalAlignment: TextInput.AlignVCenter; color: Theme.text; font.pixelSize: Theme.fs(11); clip: true }
                Text { anchors.left: parent.left; anchors.leftMargin: Theme.gapS; anchors.verticalCenter: parent.verticalCenter; visible: customDns.text === ""; text: "Custom DNS (e.g. 1.1.1.1 1.0.0.1)"; color: Theme.textMuted; font.pixelSize: Theme.fs(10) }
              }
              Rectangle { width: Theme.fs(64); height: Theme.fs(28); radius: Theme.radiusCell; color: Theme.surface
                Text { anchors.centerIn: parent; text: "Apply"; color: Theme.text; font.pixelSize: Theme.fs(10) }
                MouseArea { anchors.fill: parent; onClicked: { if (!NetworkState.validateDns(customDns.text) || customDns.text.trim() === "") { NetworkState.lastError = "Enter one or two valid DNS servers."; return } panel.confirm("Apply custom DNS", "This may reconnect the current network.", function() { NetworkState.applyDns(customDns.text.trim()) }) } }
              }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.surface }
            Row { width: parent.width
              Text { text: "Advanced IPv4"; color: Theme.text; font.bold: true; font.pixelSize: Theme.fs(13); width: parent.width - Theme.fs(90) }
              Text { text: panel.advancedOpen ? "Hide" : "Show"; color: Theme.accent; font.pixelSize: Theme.fs(11)
                MouseArea { anchors.fill: parent; onClicked: panel.advancedOpen = !panel.advancedOpen }
              }
            }
            Column { visible: panel.advancedOpen; width: parent.width; spacing: Theme.gapS
              Text { text: "Manual settings replace DHCP and can temporarily disconnect this network."; color: Theme.warning; font.pixelSize: Theme.fs(10); wrapMode: Text.WordWrap; width: parent.width }
              Row { spacing: Theme.fs(5)
                Repeater { model: [
                  { label: "Address", width: 116, key: "address" }, { label: "Prefix", width: 52, key: "prefix" },
                  { label: "Gateway", width: 126, key: "gateway" }, { label: "DNS (optional)", width: 126, key: "dns" }
                ]
                  Rectangle { required property var modelData; width: Theme.fs(modelData.width); height: Theme.fs(28); radius: Theme.radiusCell; color: Theme.bgDeep; border.color: Theme.surface
                    TextInput { id: manualInput; anchors.fill: parent; anchors.leftMargin: Theme.fs(6); anchors.rightMargin: Theme.fs(6); verticalAlignment: TextInput.AlignVCenter; color: Theme.text; font.pixelSize: Theme.fs(10); onTextChanged: { if (parent.modelData.key === "address") panel.manualAddressText = text; else if (parent.modelData.key === "prefix") panel.manualPrefixText = text; else if (parent.modelData.key === "gateway") panel.manualGatewayText = text; else panel.manualDnsText = text } }
                    Text { anchors.left: parent.left; anchors.leftMargin: Theme.fs(6); anchors.verticalCenter: parent.verticalCenter; visible: manualInput.text === ""; text: parent.modelData.label; color: Theme.textMuted; font.pixelSize: Theme.fs(9) }
                  }
                }
              }
              Row { spacing: Theme.gapS
                Rectangle { width: Theme.fs(110); height: Theme.fs(28); radius: Theme.radiusCell; color: Theme.accent
                  Text { anchors.centerIn: parent; text: "Apply manual"; color: Theme.bgDeep; font.pixelSize: Theme.fs(10); font.bold: true }
                  MouseArea { anchors.fill: parent; onClicked: panel.confirm("Apply manual IPv4", "This replaces DHCP and may disconnect the current network.", function() { NetworkState.applyManual(panel.manualAddressText, panel.manualPrefixText, panel.manualGatewayText, panel.manualDnsText) }) }
                }
                Rectangle { width: Theme.fs(110); height: Theme.fs(28); radius: Theme.radiusCell; color: Theme.surface
                  Text { anchors.centerIn: parent; text: "Restore DHCP"; color: Theme.text; font.pixelSize: Theme.fs(10) }
                  MouseArea { anchors.fill: parent; onClicked: panel.confirm("Restore DHCP", "Remove manual IPv4 and DNS overrides? The network may reconnect.", function() { NetworkState.restoreDhcp() }) }
                }
              }
            }

            Text { visible: NetworkState.lastError !== ""; text: NetworkState.lastError; color: Theme.error; font.pixelSize: Theme.fs(10); wrapMode: Text.WordWrap; width: parent.width }
          }
        }
      }

      Connections { target: NetworkState; function onQrResultChanged() { if (NetworkState.qrResult) NetworkState.panelVisible = false } }
      Rectangle { visible: panel.confirmVisible; anchors.fill: parent; color: Qt.rgba(0, 0, 0, Theme.scrimOpacity)
        Rectangle { anchors.centerIn: parent; width: Theme.fs(360); height: Theme.fs(154); radius: Theme.radiusM; color: Theme.bg; border.color: Theme.borderAccent
          Column { anchors.fill: parent; anchors.margins: Theme.gapL; spacing: Theme.gapS
            Text { text: panel.confirmTitle; color: Theme.text; font.bold: true; font.pixelSize: Theme.fs(14) }
            Text { text: panel.confirmDetail; color: Theme.textDim; font.pixelSize: Theme.fs(11); wrapMode: Text.WordWrap; width: parent.width }
            Row { spacing: Theme.gapS
              Rectangle {
                width: Theme.fs(80); height: Theme.fs(26); radius: Theme.radiusCell; color: Theme.surface
                Text { anchors.centerIn: parent; text: "Cancel"; color: Theme.text; font.pixelSize: Theme.fs(10) }
                MouseArea { anchors.fill: parent; onClicked: panel.confirmVisible = false }
              }
              Rectangle {
                width: Theme.fs(80); height: Theme.fs(26); radius: Theme.radiusCell; color: Theme.accent
                Text { anchors.centerIn: parent; text: "Continue"; color: Theme.bgDeep; font.pixelSize: Theme.fs(10); font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: { panel.confirmVisible = false; if (panel.confirmAction) panel.confirmAction() } }
              }
            }
          }
        }
      }
    }
  }
  onVisibleChanged: if (visible) keys.forceActiveFocus()
}
