pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// NetworkManager state and actions for NetworkPanel. All privileged changes
// use NetworkManager/Polkit; this code never reads or emits Wi-Fi passwords.
Singleton {
  id: root
  property bool panelVisible: false
  property string panelScreen: ""
  property bool loading: false
  property bool scanning: false
  property bool applying: false
  property bool speedTesting: false
  property bool qrLoading: false
  property string lastError: ""
  property bool wifiEnabled: false
  property string connType: "none"
  property string iface: ""
  property string connectionState: "disconnected"
  property string profile: ""
  property string ssid: ""
  property int signalPct: 0
  property string ipAddress: "-"
  property string gateway: "-"
  property var dnsServers: []
  property string ipv4Method: ""
  property var wifiNetworks: []
  property var speedResult: null
  property var qrResult: null

  readonly property string backend: Quickshell.env("NETWORK_CONTROL") ||
    Quickshell.env("HOME") + "/.config/hypr/scripts/network-control"
  readonly property var dnsProviders: [
    { id: "automatic", label: "Automatic", values: "" },
    { id: "cloudflare", label: "Cloudflare", values: "1.1.1.1 1.0.0.1" },
    { id: "google", label: "Google", values: "8.8.8.8 8.8.4.4" },
    { id: "quad9", label: "Quad9", values: "9.9.9.9 149.112.112.112" }
  ]

  function togglePanel(screenName) {
    if (panelVisible && panelScreen === screenName) { panelVisible = false; return }
    if (screenName === "") return
    panelScreen = screenName
    panelVisible = true
    refresh()
  }
  function formatBytes(n) {
    if (!(n >= 0)) return "-"
    if (n < 1024) return n.toFixed(0) + " B/s"
    if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB/s"
    return (n / (1024 * 1024)).toFixed(1) + " MB/s"
  }
  function validateIp(ip) {
    const parts = ip.trim().split(".")
    return parts.length === 4 && parts.every(p => /^\d{1,3}$/.test(p) && Number(p) <= 255)
  }
  function validateDns(dns) {
    const values = dns.trim() === "" ? [] : dns.trim().split(/\s+/)
    return values.length <= 2 && values.every(validateIp)
  }
  function refresh() { if (!statusProc.running) statusProc.running = true }
  function scan() {
    if (!wifiEnabled || scanning) return
    scanning = true; lastError = ""; scanProc.command = [backend, "scan"]; scanProc.running = true
  }
  function action(args) {
    if (applying) return
    applying = true; lastError = ""; actionProc.command = [backend].concat(args); actionProc.running = true
  }
  function setWifi(enabled) { action(["wifi", enabled ? "on" : "off"]) }
  function disconnect() { action(["disconnect", iface]) }
  function connectOpen(bssid) { action(["connect", bssid]) }
  // Secure networks open NetworkManager's interactive terminal UI. No password
  // is routed through QML, a process argument, or this state object.
  function connectSecure() { action(["nmtui"]) }
  function applyDns(values) { action(["dns", values === "" ? "automatic" : "custom", values]) }
  function restoreDhcp() { action(["ipv4", "automatic"]) }
  function applyManual(address, prefix, gatewayValue, dns) {
    if (!validateIp(address) || !validateIp(gatewayValue) || !/^\d{1,2}$/.test(prefix) || Number(prefix) > 32 || !validateDns(dns)) {
      lastError = "Enter a valid IPv4 address, prefix, gateway, and up to two DNS servers."
      return
    }
    action(["ipv4", "manual", address, prefix, gatewayValue, dns])
  }
  function runSpeedTest() {
    if (speedTesting) return
    speedTesting = true; speedResult = null; lastError = ""; speedProc.command = [backend, "speed-test"]; speedProc.running = true
  }
  function shareWifi() {
    if (qrLoading || connType !== "wifi") return
    qrLoading = true; qrResult = null; lastError = ""; qrProc.command = [backend, "qr"]; qrProc.running = true
  }

  Process {
    id: statusProc; command: [root.backend, "status"]
    stdout: StdioCollector { id: statusOut }
    onStarted: root.loading = true
    onExited: function(code) {
      root.loading = false
      if (code !== 0) { root.lastError = "NetworkManager status is unavailable."; return }
      try {
        const data = JSON.parse(statusOut.text)
        root.wifiEnabled = data.wifiEnabled === true; root.connType = data.connectionType || "none"
        root.iface = data.interface || ""; root.connectionState = data.connectionState || "disconnected"
        root.profile = data.profile || ""; root.ssid = data.ssid || ""; root.signalPct = Number(data.signal) || 0
        root.ipAddress = data.ipv4 || "-"; root.gateway = data.gateway || "-"; root.dnsServers = data.dns || []
        root.ipv4Method = data.ipv4Method || ""
      } catch (error) { root.lastError = "NetworkManager returned invalid status." }
    }
  }
  Process {
    id: scanProc; stdout: StdioCollector { id: scanOut }
    onExited: function(code) {
      root.scanning = false
      if (code !== 0) { root.lastError = "Wi-Fi scan failed."; return }
      try { root.wifiNetworks = JSON.parse(scanOut.text) } catch (error) { root.lastError = "Wi-Fi scan returned invalid data." }
    }
  }
  Process {
    id: actionProc
    onExited: function(code) {
      root.applying = false
      if (code !== 0) root.lastError = "NetworkManager did not apply that change. Check authorization or connection details."
      root.refresh()
    }
  }
  Process {
    id: speedProc; stdout: StdioCollector { id: speedOut }
    onExited: function(code) {
      root.speedTesting = false
      if (code !== 0) { root.lastError = "Speed test failed. Check your internet connection."; return }
      try { root.speedResult = JSON.parse(speedOut.text) } catch (error) { root.lastError = "Speed test returned invalid data." }
    }
  }
  Process {
    id: qrProc; stdout: StdioCollector { id: qrOut }
    onExited: function(code) {
      root.qrLoading = false
      if (code !== 0) { root.lastError = "Could not create a Wi-Fi QR code. NetworkManager may require authorization."; return }
      try { root.qrResult = JSON.parse(qrOut.text) } catch (error) { root.lastError = "Wi-Fi QR creation returned invalid data." }
    }
  }
  Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
}
