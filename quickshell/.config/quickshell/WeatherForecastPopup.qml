import QtQuick
import Quickshell

// 10-day daily forecast, anchored below the bar's weather readout.
PopupWindow {
  id: popup
  required property Item anchorItem

  visible: false
  grabFocus: true
  anchor.item: anchorItem
  anchor.edges: Edges.Bottom
  anchor.gravity: Edges.Bottom
  anchor.margins.top: Theme.gapS
  implicitWidth: Theme.fs(300)
  implicitHeight: body.implicitHeight + Theme.gapL * 2

  Rectangle { anchors.fill: parent; color: Theme.bg }

  Item {
    id: content
    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: popup.visible = false

    Column {
      id: body
      anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
      anchors.margins: Theme.gapL
      spacing: Theme.gapXS

      Text {
        text: WeatherState.hasData
              ? WeatherState.codeLabel(WeatherState.current.code) + " · feels "
                + WeatherState.fmtTemp(WeatherState.current.feels)
              : (WeatherState.errorText || "Loading forecast…")
        color: Theme.textDim
        font.family: Theme.uiFamily
        font.pixelSize: Theme.fs(12)
        bottomPadding: Theme.gapS
      }

      Repeater {
        model: WeatherState.daily
        delegate: Row {
          required property var modelData
          required property int index
          width: body.width
          spacing: Theme.gapS

          Text {
            width: Theme.fs(44)
            text: index === 0 ? "Today" : WeatherState.fmtDay(modelData.date)
            color: Theme.text
            font.family: Theme.uiFamily
            font.pixelSize: Theme.fs(13)
          }
          Text {
            width: Theme.fs(24)
            text: WeatherState.codeGlyph(modelData.code, true)
            color: Theme.text
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(15)
          }
          Text {
            width: Theme.fs(110)
            text: WeatherState.codeLabel(modelData.code)
            color: Theme.textDim
            font.family: Theme.uiFamily
            font.pixelSize: Theme.fs(12)
            elide: Text.ElideRight
          }
          Text {
            width: Theme.fs(36)
            text: modelData.precipMax > 0 ? modelData.precipMax + "%" : ""
            color: Theme.textDim
            font.family: Theme.uiFamily
            font.pixelSize: Theme.fs(12)
          }
          Text {
            text: Math.round(modelData.tMax) + "° / " + Math.round(modelData.tMin) + "°"
            color: Theme.text
            font.family: Theme.uiFamily
            font.pixelSize: Theme.fs(13)
          }
        }
      }
    }
  }

  onVisibleChanged: if (visible) { WeatherState.maybeRefresh(); content.forceActiveFocus() }
}
