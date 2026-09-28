import QtQuick

// One readout column in the battery panel: small-caps label, large figure, dim
// qualifier underneath.
//
// Deliberately not MetricCard: that is a fixed Theme.smallCardW/H Card with a
// surface, a border and a progress bar, and its figure is locked at fs(13).
// The battery panel wants borderless tiles sitting directly on the panel
// background with the figure as the dominant element, so bending MetricCard
// into shape would mean overriding almost all of it.
Item {
  id: root
  property string label: ""
  property string primary: ""
  property string secondary: ""
  // False when the figure is genuinely unknown, which reads as a placeholder
  // rather than as a confident zero.
  property bool available: true

  implicitWidth: Theme.fs(140)
  implicitHeight: body.implicitHeight

  Column {
    id: body
    width: root.width
    spacing: Theme.fs(2)

    Text {
      text: root.label
      color: Theme.textMuted
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(10)
      font.bold: true
      font.letterSpacing: Theme.fs(1)
    }

    Text {
      width: parent.width
      text: root.available ? root.primary : "—"
      color: root.available ? Theme.text : Theme.textMuted
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(19)
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: root.secondary
      color: Theme.textMuted
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(10)
      elide: Text.ElideRight
    }
  }
}
