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
  property bool qrLoading: false
  property bool speedTestRunning: false
  property bool speedTestVisible: false
  property bool speedTestCancelled: false
  property string speedTestScreen: ""
  property string speedTestConnection: ""
  property string speedTestPhase: ""
  property real downloadMbps: 0
  property real uploadMbps: 0
  property real downloadPeakMbps: 0
  property real uploadPeakMbps: 0
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
  property var qrResult: null

  readonly property string backend: Quickshell.env("NETWORK_CONTROL") ||
    Quickshell.env("HOME") + "/.config/hypr/scripts/network-control"
  readonly property string speedTest: Quickshell.env("HOME") + "/.local/bin/network-speedtest"
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
  // The backend prefixes its own name onto every diagnostic and may emit more
  // than one line, so the panel shows just the last, most specific sentence.
  function backendError(text) {
    const lines = []
    const raw = String(text || "").split("\n")
    for (let i = 0; i < raw.length; i++) {
      const line = raw[i].replace(/^network-control:\s*/, "").trim()
      if (line !== "") lines.push(line)
    }
    return lines.length > 0 ? lines[lines.length - 1] : ""
  }
  function shareWifi() {
    if (qrLoading || connType !== "wifi") return
    qrLoading = true; qrResult = null; lastError = ""; qrProc.command = [backend, "qr"]; qrProc.running = true
  }
  function speedTestLabel() {
    if (connType === "wifi")
      return ssid || iface || "Wi-Fi"
    if (connType !== "" && connType !== "none")
      return connType
    return ssid || iface || "Network"
  }
  function runSpeedTest(screenName) {
    if (speedTestRunning || screenName === "")
      return
    speedTestScreen = screenName
    speedTestConnection = speedTestLabel()
    speedTestPhase = "download"
    speedTestCancelled = false
    downloadMbps = 0; uploadMbps = 0
    downloadPeakMbps = 0; uploadPeakMbps = 0
    speedTestVisible = true
    speedTestRunning = true; lastError = ""; speedTestProc.running = true
  }
  function closeSpeedTest() {
    speedTestVisible = false
    if (speedTestRunning) {
      speedTestCancelled = true
      speedTestProc.running = false
    }
  }
  function handleSpeedTestLine(line) {
    let sample
    try { sample = JSON.parse(line) } catch (error) { return }
    const mbps = Number(sample.mbps)
    if (!isFinite(mbps) || mbps < 0)
      return
    if (sample.phase === "download") {
      speedTestPhase = "download"
      downloadMbps = mbps
      downloadPeakMbps = Math.max(downloadPeakMbps, mbps)
    } else if (sample.phase === "upload") {
      speedTestPhase = "upload"
      uploadMbps = mbps
      uploadPeakMbps = Math.max(uploadPeakMbps, mbps)
    }
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
    id: qrProc
    stdout: StdioCollector { id: qrOut }
    stderr: StdioCollector { id: qrErr }
    onExited: function(code) {
      root.qrLoading = false
      if (code !== 0) {
        root.lastError = root.backendError(qrErr.text) || "Could not create a Wi-Fi QR code."
        return
      }
      try { root.qrResult = JSON.parse(qrOut.text) } catch (error) { root.lastError = "Wi-Fi QR creation returned invalid data." }
    }
  }
  Process {
    id: speedTestProc
    command: [root.speedTest, "--stream-json"]
    stdout: SplitParser { onRead: line => root.handleSpeedTestLine(line) }
    stderr: StdioCollector { id: speedTestErr }
    onExited: function(code) {
      root.speedTestRunning = false
      if (code !== 0 && !root.speedTestCancelled)
        root.lastError = speedTestErr.text.trim() || "Network speed test failed."
      root.speedTestPhase = root.speedTestCancelled ? "" : (code === 0 ? "complete" : "error")
    }
  }
  Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
}
