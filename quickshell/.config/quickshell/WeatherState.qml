pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Weather from Open-Meteo (api.open-meteo.com).
//
// Chosen because it needs no API key and no account, and returns current
// conditions, hourly precipitation probability and a daily forecast in one
// request. Conditions arrive as WMO codes, mapped to glyph + label below.
Singleton {
  id: root

  // Location comes from weather.json next to this file; Chicago defaults.
  property real latitude: 41.8781
  property real longitude: -87.6298
  property string timezone: "America/Chicago"

  FileView {
    path: Qt.resolvedUrl("weather.json")
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        const c = JSON.parse(text())
        if (isFinite(c.latitude)) root.latitude = c.latitude
        if (isFinite(c.longitude)) root.longitude = c.longitude
        if (typeof c.timezone === "string" && c.timezone !== "") root.timezone = c.timezone
        root.refresh()
      } catch (e) {}
    }
  }

  // idle | loading | ok | error
  property string status: "idle"
  property string errorText: ""
  // Kept so a failed refresh shows the last good data rather than blanking.
  property double lastFetchMs: 0
  readonly property int refreshIntervalMs: 15 * 60 * 1000

  property var current: null      // { temp, feels, humidity, code, wind, isDay, precip }
  property var hourly: []         // [{ time, temp, precipProb, code }]
  property var daily: []          // [{ date, code, tMax, tMin, precipMax, sunrise, sunset }]

  readonly property bool hasData: current !== null

  Component.onCompleted: root.maybeRefresh()

  // --- fetching --------------------------------------------------------------

  // Only actually hits the network if the cached result has expired.
  function maybeRefresh() {
    const age = Date.now() - root.lastFetchMs
    if (root.hasData && age < root.refreshIntervalMs)
      return
    root.refresh()
  }

  function refresh() {
    if (fetchProc.running)
      return
    root.status = "loading"
    fetchProc.command = ["curl", "-sS", "--max-time", "15", "-G",
      "--data-urlencode", "latitude=" + root.latitude,
      "--data-urlencode", "longitude=" + root.longitude,
      "--data-urlencode", "current=temperature_2m,apparent_temperature,"
        + "relative_humidity_2m,weather_code,wind_speed_10m,is_day,precipitation",
      "--data-urlencode", "hourly=temperature_2m,precipitation_probability,weather_code",
      "--data-urlencode", "daily=weather_code,temperature_2m_max,temperature_2m_min,"
        + "precipitation_probability_max,sunrise,sunset",
      "--data-urlencode", "temperature_unit=fahrenheit",
      "--data-urlencode", "wind_speed_unit=mph",
      "--data-urlencode", "timezone=" + root.timezone,
      "--data-urlencode", "forecast_days=10",
      "https://api.open-meteo.com/v1/forecast"]
    fetchProc.running = true
  }

  // The cache check keeps this to one request per 15 minutes.
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.maybeRefresh()
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      onTextChanged: {
        if (text.trim() === "")
          return
        var d = null
        try {
          d = JSON.parse(text)
        } catch (e) {
          root.fail("Malformed weather response")
          return
        }
        if (!d || d.error || !d.current) {
          root.fail(d && d.reason ? d.reason : "Weather unavailable")
          return
        }

        const c = d.current
        root.current = {
          temp: c.temperature_2m,
          feels: c.apparent_temperature,
          humidity: c.relative_humidity_2m,
          code: c.weather_code,
          wind: c.wind_speed_10m,
          isDay: c.is_day === 1,
          precip: c.precipitation
        }

        const hs = []
        if (d.hourly && d.hourly.time) {
          for (var i = 0; i < d.hourly.time.length; i++) {
            hs.push({
              time: d.hourly.time[i],
              temp: d.hourly.temperature_2m[i],
              precipProb: d.hourly.precipitation_probability[i],
              code: d.hourly.weather_code[i]
            })
          }
        }
        root.hourly = hs

        const ds = []
        if (d.daily && d.daily.time) {
          for (var j = 0; j < d.daily.time.length; j++) {
            ds.push({
              date: d.daily.time[j],
              code: d.daily.weather_code[j],
              tMax: d.daily.temperature_2m_max[j],
              tMin: d.daily.temperature_2m_min[j],
              precipMax: d.daily.precipitation_probability_max[j],
              sunrise: d.daily.sunrise[j],
              sunset: d.daily.sunset[j]
            })
          }
        }
        root.daily = ds

        root.lastFetchMs = Date.now()
        root.status = "ok"
        root.errorText = ""
      }
    }
    stderr: StdioCollector { id: fetchErr }
    onExited: function (code) {
      if (code !== 0 && root.status === "loading")
        root.fail(fetchErr.text.trim() || "Could not reach Open-Meteo")
    }
  }

  function fail(msg) {
    root.errorText = msg
    // Keep any previously fetched data on screen; only the badge changes.
    root.status = "error"
  }

  // --- upcoming rain ---------------------------------------------------------

  readonly property int rainThreshold: 40

  // First upcoming hour (within ~12h) whose precipitation probability crosses
  // the threshold. null when no rain is expected.
  readonly property var rainSoon: {
    if (root.hourly.length === 0)
      return null
    const nowIso = Qt.formatDateTime(new Date(), "yyyy-MM-ddThh:00")
    var start = -1
    for (var i = 0; i < root.hourly.length; i++) {
      if (root.hourly[i].time >= nowIso) { start = i; break }
    }
    if (start < 0)
      return null
    const end = Math.min(root.hourly.length, start + 12)
    for (var j = start; j < end; j++) {
      if (root.hourly[j].precipProb >= root.rainThreshold) {
        return {
          time: root.hourly[j].time,
          prob: root.hourly[j].precipProb,
          hoursAway: j - start
        }
      }
    }
    return null
  }

  // Hourly entries from the current hour onward, for the forecast strip.
  readonly property var upcomingHours: {
    if (root.hourly.length === 0)
      return []
    const nowIso = Qt.formatDateTime(new Date(), "yyyy-MM-ddThh:00")
    for (var i = 0; i < root.hourly.length; i++) {
      if (root.hourly[i].time >= nowIso)
        return root.hourly.slice(i, i + 12)
    }
    return []
  }

  // --- WMO code mapping ------------------------------------------------------

  // Codepoints verified against the installed JetBrainsMono Nerd Font cmap.
  function codeGlyph(code, isDay) {
    switch (code) {
    case 0:  return isDay ? String.fromCodePoint(0xf0599)  // md-weather_sunny
                          : String.fromCodePoint(0xf0594)  // md-weather_night
    case 1:
    case 2:  return isDay ? String.fromCodePoint(0xf0595)  // md-weather_partly_cloudy
                          : String.fromCodePoint(0xf0f31)  // md-weather_night_partly_cloudy
    case 3:  return String.fromCodePoint(0xf0590)          // md-weather_cloudy
    case 45:
    case 48: return String.fromCodePoint(0xf0591)          // md-weather_fog
    case 51: case 53: case 55:
    case 56: case 57:
             return String.fromCodePoint(0xf0f33)          // md-weather_partly_rainy
    case 61: case 63:
    case 66: case 67:
             return String.fromCodePoint(0xf0597)          // md-weather_rainy
    case 65: return String.fromCodePoint(0xf0596)          // md-weather_pouring
    case 71: case 73: case 75: case 77:
             return String.fromCodePoint(0xf0598)          // md-weather_snowy
    case 80: case 81:
             return String.fromCodePoint(0xf0597)          // md-weather_rainy
    case 82: return String.fromCodePoint(0xf0596)          // md-weather_pouring
    case 85: case 86:
             return String.fromCodePoint(0xf0598)          // md-weather_snowy
    case 95: return String.fromCodePoint(0xf0593)          // md-weather_lightning
    case 96: case 99:
             return String.fromCodePoint(0xf067e)          // md-weather_lightning_rainy
    default: return String.fromCodePoint(0xf0590)          // md-weather_cloudy
    }
  }

  function codeLabel(code) {
    switch (code) {
    case 0:  return "Clear"
    case 1:  return "Mainly clear"
    case 2:  return "Partly cloudy"
    case 3:  return "Overcast"
    case 45: return "Fog"
    case 48: return "Freezing fog"
    case 51: return "Light drizzle"
    case 53: return "Drizzle"
    case 55: return "Heavy drizzle"
    case 56: case 57: return "Freezing drizzle"
    case 61: return "Light rain"
    case 63: return "Rain"
    case 65: return "Heavy rain"
    case 66: case 67: return "Freezing rain"
    case 71: return "Light snow"
    case 73: return "Snow"
    case 75: return "Heavy snow"
    case 77: return "Snow grains"
    case 80: return "Light showers"
    case 81: return "Showers"
    case 82: return "Violent showers"
    case 85: return "Snow showers"
    case 86: return "Heavy snow showers"
    case 95: return "Thunderstorm"
    case 96: case 99: return "Thunderstorm with hail"
    default: return "Unknown"
    }
  }

  // Day/night for an hourly timestamp, taken from that date's sunrise/sunset so
  // the forecast strip does not show a sun at 2 AM. ISO strings of identical
  // format compare correctly as strings.
  function isDayAt(iso) {
    const date = iso.substring(0, 10)
    for (var i = 0; i < root.daily.length; i++) {
      if (root.daily[i].date === date)
        return iso >= root.daily[i].sunrise && iso < root.daily[i].sunset
    }
    const h = parseInt(iso.substring(11, 13), 10)
    return h >= 6 && h < 20
  }

  function fmtTemp(t) {
    return (isFinite(t) ? Math.round(t) : "--") + "°F"
  }

  function fmtHour(iso) {
    // "2026-08-22T18:00" -> "6 PM"
    const d = Date.fromLocaleString(Qt.locale(), iso, "yyyy-MM-ddThh:mm")
    return isNaN(d.getTime()) ? iso.substring(11, 16)
                              : Qt.formatDateTime(d, "h AP")
  }

  function fmtDay(iso) {
    const d = Date.fromLocaleString(Qt.locale(), iso, "yyyy-MM-dd")
    return isNaN(d.getTime()) ? iso : Qt.formatDateTime(d, "ddd")
  }

  function fmtClock(iso) {
    const d = Date.fromLocaleString(Qt.locale(), iso, "yyyy-MM-ddThh:mm")
    return isNaN(d.getTime()) ? iso.substring(11, 16)
                              : Qt.formatDateTime(d, "h:mm AP")
  }
}
