pragma Singleton
import Quickshell
import QtQuick

Singleton {
  id: root

  // Right-click cycles through these, looping back to the start.
  readonly property var formats: [
    "dddd h:mm AP",
    "h:mm AP",
    "dddd, MMMM d",
    "yyyy-MM-dd"
  ]
  property int formatIndex: 0

  // Empty tzId means "follow the system clock/timezone".
  property string tzId: ""
  readonly property string tzLabel: tzId === "" ? "Local (America/Chicago)" : tzId

  function cycleFormat() {
    formatIndex = (formatIndex + 1) % formats.length
  }

  // Quickshell's QML JS engine has no Intl support (verified empirically:
  // `typeof Intl === "undefined"`), so zone conversion can't go through
  // Intl.DateTimeFormat. Every zone below (plus UTC) follows the same
  // post-2007 US DST rule, so the offset is computed directly instead:
  // 2nd Sunday of March 2am (std) -> 1st Sunday of November 2am (dst).
  readonly property var zoneOffsets: ({
    "America/New_York": { std: -300, dst: true },
    "America/Denver": { std: -420, dst: true },
    "America/Los_Angeles": { std: -480, dst: true },
    "UTC": { std: 0, dst: false }
  })

  function nthSundayUtc(year, month, n) {
    const firstDow = new Date(Date.UTC(year, month, 1)).getUTCDay()
    const firstSunday = 1 + ((7 - firstDow) % 7)
    return firstSunday + (n - 1) * 7
  }

  function usOffsetMinutes(utcMs, stdMinutes, hasDst) {
    if (!hasDst)
      return stdMinutes

    const year = new Date(utcMs + stdMinutes * 60000).getUTCFullYear()
    const marchSunday = nthSundayUtc(year, 2, 2)
    const novSunday = nthSundayUtc(year, 10, 1)
    const startUtc = Date.UTC(year, 2, marchSunday, 2, 0, 0) - stdMinutes * 60000
    const endUtc = Date.UTC(year, 10, novSunday, 2, 0, 0) - (stdMinutes + 60) * 60000
    return (utcMs >= startUtc && utcMs < endUtc) ? stdMinutes + 60 : stdMinutes
  }

  // Re-expresses the current instant as a "fake local" Date carrying the
  // wall-clock fields of tzId, so Qt.formatDateTime (which always reads
  // local getters) prints the right numbers without touching system TZ.
  function zonedDate() {
    const zone = zoneOffsets[tzId]
    if (tzId === "" || !zone)
      return clock.date

    const utcMs = clock.date.getTime()
    const offsetMinutes = usOffsetMinutes(utcMs, zone.std, zone.dst)
    const wall = new Date(utcMs + offsetMinutes * 60000)
    return new Date(wall.getUTCFullYear(), wall.getUTCMonth(), wall.getUTCDate(),
                     wall.getUTCHours(), wall.getUTCMinutes(), wall.getUTCSeconds())
  }

  readonly property string displayText: Qt.formatDateTime(zonedDate(), formats[formatIndex])

  // Seconds, because the bar clock shows them.
  SystemClock {
    id: clock
    precision: SystemClock.Seconds
  }
}
