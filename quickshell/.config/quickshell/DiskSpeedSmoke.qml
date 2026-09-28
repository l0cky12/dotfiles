import QtQuick
import Quickshell

// Headless checks for DiskState's picker and sample handling, plus the shared
// gauge's disk scale. Nothing here starts the backend.
Scope {
  id: smoke
  Component { id: gaugeComponent; SpeedTestGauge {} }

  property int failures: 0
  function check(name, condition) {
    if (condition) console.log("ok   " + name)
    else { console.log("FAIL " + name); failures += 1 }
  }

  Component.onCompleted: {
    const network = gaugeComponent.createObject(null)
    check("network gauge keeps its Mbps defaults",
      network.unit === "Mbps" && network.scaleFor(59) === 100 && network.scaleFor(940) === 1600)
    network.destroy()
    const disk = gaugeComponent.createObject(null, { unit: "MB/s", scaleSteps: DiskState.scaleSteps })
    check("disk gauge puts NVMe reads mid-arc", disk.scaleFor(2750) === 4000)
    check("disk gauge keeps 4K random readable", disk.scaleFor(27) === 50)
    check("disk gauge extends past its last step", disk.scaleFor(9000) === 16000)
    disk.destroy()

    const listing = {
      default: "nvme0n1",
      disks: [
        { name: "nvme0n1", state: "ready", system: true },
        { name: "sda", state: "unavailable", reason: "read-only" },
        { name: "sdc", state: "mountable", mountDevice: "/dev/sdc1" }
      ]
    }
    check("system disk is preselected", DiskState.defaultIndex(listing) === 0)
    check("selection skips unavailable disks", DiskState.nextSelectable(listing.disks, 0, 1) === 2)
    check("selection wraps backwards", DiskState.nextSelectable(listing.disks, 0, -1) === 2)
    check("mountable disks count as testable", DiskState.testable(listing.disks).length === 2)
    check("unmounted default falls back to first testable disk",
      DiskState.defaultIndex({ default: "sda", disks: listing.disks }) === 0)
    check("sizes use binary units", DiskState.formatSize(1000204886016) === "931.5 GiB")
    check("backend prefix is stripped from errors",
      DiskState.backendError("disk-speedtest: read failed: Input/output error\n") === "read failed: Input/output error")

    DiskState.handleLine('{"phase":"start","disk":{"model":"WD_BLACK SN770 1TB","mountpoint":"/home","fstype":"btrfs","encrypted":true},"bytes":1073741824,"reduced":true,"direct":false}')
    check("start line fills the header",
      DiskState.headerDetail() === "/home · btrfs · encrypted · 1.0 GiB test · reduced test size")
    check("start line reports buffered I/O", DiskState.direct === false)
    DiskState.handleLine('{"phase":"write","mbs":1800.5}')
    DiskState.handleLine('{"phase":"write","mbs":900}')
    check("write samples track value and peak", DiskState.writeMbs === 900 && DiskState.writePeakMbs === 1800.5)
    DiskState.handleLine('{"phase":"random","mbs":27.3,"iops":6676,"latency_us":149.8}')
    check("random samples carry IOPS and latency", DiskState.iops === 6676 && DiskState.phase === "random")
    DiskState.handleLine("not json")
    check("invalid lines are ignored", DiskState.phase === "random")
    DiskState.finish(1, "disk-speedtest: random failed: No such device\n")
    check("a failure marks only the interrupted phase",
      DiskState.failedPhase === "random" && DiskState.writeMbs === 900 && DiskState.phase === "error")
    check("the failure message is shown", DiskState.lastError === "random failed: No such device")
    DiskState.handleLine('{"phase":"complete","write":1837.2,"read":2750.8,"random":27.3,"iops":6676,"latency_us":149.8,"direct":true}')
    check("complete settles dials on phase averages", DiskState.readMbs === 2750.8 && DiskState.direct === true)
  }
  Timer {
    interval: 100
    running: true
    onTriggered: {
      console.log(smoke.failures === 0 ? "ok: Disk speed test logic" : "FAIL: Disk speed test logic")
      Qt.quit()
    }
  }
}
