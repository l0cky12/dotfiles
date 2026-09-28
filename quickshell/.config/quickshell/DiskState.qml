pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Disk speed test state for DiskSpeedOverlay. The backend only writes a
// temporary file on a mounted filesystem; unmounted drives are mounted through
// udisksctl, so nothing here needs root.
Singleton {
  id: root
  property bool overlayVisible: false
  property string overlayScreen: ""
  // "" | loading | pick | mount | start | write | read | random | complete | error
  property string phase: ""
  property bool running: false
  property bool cancelled: false
  property var disks: []
  property int selectedIndex: -1
  property string diskName: ""
  property var disk: ({})
  property real testBytes: 0
  property bool reduced: false
  property bool direct: true
  property real writeMbs: 0
  property real readMbs: 0
  property real randomMbs: 0
  property real writePeakMbs: 0
  property real readPeakMbs: 0
  property real randomPeakMbs: 0
  property int iops: 0
  property real latencyUs: 0
  property string failedPhase: ""
  property string lastError: ""

  readonly property string backend: Quickshell.env("DISK_SPEEDTEST") ||
    Quickshell.env("HOME") + "/.local/bin/disk-speedtest"
  readonly property var scaleSteps: [10, 25, 50, 100, 250, 500, 1000, 2000, 4000, 8000]
  readonly property var testPhases: ["write", "read", "random"]
  readonly property int testableCount: testable(disks).length

  function isTestable(entry) {
    return !!entry && (entry.state === "ready" || entry.state === "mountable")
  }
  function testable(list) {
    return (list || []).filter(isTestable)
  }
  // Step from index in direction delta to the next disk that can be tested,
  // staying put when there is none.
  function nextSelectable(list, index, delta) {
    const count = (list || []).length
    for (let step = 1; step <= count; step++) {
      const candidate = ((index + delta * step) % count + count) % count
      if (isTestable(list[candidate]))
        return candidate
    }
    return index
  }
  function defaultIndex(listing) {
    const list = listing.disks || []
    const preferred = list.findIndex(entry => entry.name === listing.default && isTestable(entry))
    return preferred >= 0 ? preferred : list.findIndex(isTestable)
  }
  function formatSize(bytes) {
    const units = [["TiB", Math.pow(1024, 4)], ["GiB", Math.pow(1024, 3)], ["MiB", Math.pow(1024, 2)]]
    for (let i = 0; i < units.length; i++)
      if (bytes >= units[i][1])
        return (bytes / units[i][1]).toFixed(1) + " " + units[i][0]
    return Math.max(0, Math.round(bytes)) + " B"
  }
  function cardDetail(entry) {
    const parts = [formatSize(entry.size)]
    if (entry.transport) parts.push(entry.transport)
    if (entry.state === "ready") parts.push(entry.mountpoint)
    else if (entry.state === "mountable") parts.push("not mounted, mounts for the test")
    else parts.push(entry.reason || "unavailable")
    return parts.join(" · ")
  }
  function headerTitle() {
    return disk.model || disk.name || "Disk"
  }
  function headerDetail() {
    const parts = []
    if (disk.mountpoint) parts.push(disk.mountpoint)
    if (disk.fstype) parts.push(disk.fstype)
    if (disk.encrypted) parts.push("encrypted")
    if (testBytes > 0) parts.push(formatSize(testBytes) + " test")
    if (reduced) parts.push("reduced test size")
    return parts.join(" · ")
  }
  function randomDetail() {
    return iops > 0 ? iops.toLocaleString(Qt.locale(), "f", 0) + " IOPS · " + latencyUs.toFixed(0) + " µs" : ""
  }
  // The backend prefixes its name onto every diagnostic; show the last line.
  function backendError(text) {
    const lines = String(text || "").split("\n")
      .map(line => line.replace(/^disk-speedtest:\s*/, "").trim())
      .filter(line => line !== "")
    return lines.length > 0 ? lines[lines.length - 1] : ""
  }

  function open(screenName) {
    if (running || listProc.running || screenName === "")
      return
    overlayScreen = screenName
    overlayVisible = true
    diskName = ""; disk = ({}); failedPhase = ""; lastError = ""
    phase = "loading"
    listProc.running = true
  }
  function applyListing(text) {
    let listing
    try { listing = JSON.parse(text) } catch (error) {
      lastError = "The disk list was not valid JSON."; phase = "error"; return
    }
    disks = listing.disks || []
    const usable = testable(disks)
    if (usable.length === 0) {
      lastError = "No disk can be tested."; phase = "error"
    } else if (usable.length === 1) {
      start(usable[0].name)
    } else {
      selectedIndex = defaultIndex(listing)
      phase = "pick"
    }
  }
  function moveSelection(delta) {
    if (phase === "pick")
      selectedIndex = nextSelectable(disks, selectedIndex, delta)
  }
  function choose(index) {
    if (phase === "pick" && isTestable(disks[index]))
      start(disks[index].name)
  }
  function start(name) {
    if (running)
      return
    diskName = name
    disk = disks.find(entry => entry.name === name) || ({ name: name })
    testBytes = 0; reduced = false; direct = true
    writeMbs = 0; readMbs = 0; randomMbs = 0
    writePeakMbs = 0; readPeakMbs = 0; randomPeakMbs = 0
    iops = 0; latencyUs = 0
    failedPhase = ""; lastError = ""
    cancelled = false
    phase = "start"
    testProc.command = [backend, "--stream-json", "--disk", name]
    running = true
    testProc.running = true
  }
  function runAgain() {
    if (!running && diskName !== "" && (phase === "complete" || phase === "error"))
      start(diskName)
  }
  function changeDisk() {
    if (running || testableCount < 2)
      return
    selectedIndex = Math.max(0, disks.findIndex(entry => entry.name === diskName))
    phase = "pick"
  }
  function close() {
    overlayVisible = false
    if (listProc.running)
      listProc.running = false
    if (running) {
      cancelled = true
      testProc.running = false
    }
  }
  function handleLine(line) {
    let sample
    try { sample = JSON.parse(line) } catch (error) { return }
    if (sample.phase === "mount") {
      phase = "mount"
    } else if (sample.phase === "start") {
      phase = "start"
      if (sample.disk) disk = sample.disk
      testBytes = Number(sample.bytes) || 0
      reduced = sample.reduced === true
      direct = sample.direct !== false
    } else if (testPhases.indexOf(sample.phase) >= 0) {
      const mbs = Number(sample.mbs)
      if (!isFinite(mbs) || mbs < 0)
        return
      phase = sample.phase
      if (sample.phase === "write") {
        writeMbs = mbs; writePeakMbs = Math.max(writePeakMbs, mbs)
      } else if (sample.phase === "read") {
        readMbs = mbs; readPeakMbs = Math.max(readPeakMbs, mbs)
      } else {
        randomMbs = mbs; randomPeakMbs = Math.max(randomPeakMbs, mbs)
        iops = Number(sample.iops) || 0
        latencyUs = Number(sample.latency_us) || 0
      }
    } else if (sample.phase === "complete") {
      // Settle every dial on the whole-phase average, not its last second.
      writeMbs = Number(sample.write) || 0
      readMbs = Number(sample.read) || 0
      randomMbs = Number(sample.random) || 0
      iops = Number(sample.iops) || 0
      latencyUs = Number(sample.latency_us) || 0
      direct = sample.direct !== false
    }
  }
  function finish(code, errorText) {
    running = false
    if (cancelled) {
      phase = ""
      return
    }
    if (code === 0) {
      phase = "complete"
      return
    }
    // Completed phases keep their results; only the interrupted one is marked.
    failedPhase = testPhases.indexOf(phase) >= 0 ? phase : ""
    lastError = backendError(errorText) || "Disk speed test failed."
    phase = "error"
  }

  Process {
    id: listProc
    command: [root.backend, "--list-json"]
    stdout: StdioCollector { id: listOut }
    stderr: StdioCollector { id: listErr }
    onExited: function(code) {
      if (!root.overlayVisible)
        return
      if (code !== 0) {
        root.lastError = root.backendError(listErr.text) || "Could not list disks."
        root.phase = "error"
        return
      }
      root.applyListing(listOut.text)
    }
  }
  Process {
    id: testProc
    stdout: SplitParser { onRead: line => root.handleLine(line) }
    stderr: StdioCollector { id: testErr }
    onExited: function(code) { root.finish(code, testErr.text) }
  }
}
