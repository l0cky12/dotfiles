import QtQuick

// One black capsule on the bar. The bar itself paints nothing, so an island is
// the only background any bar module ever sits on -- modules stay transparent
// and let this shape carry the contrast.
//
// Children are declared directly and land in the internal Row:
//
//   BarIsland {
//     NetworkIcon {}
//     AudioIcon {}
//   }
//
// Sized to its content, so an island shrinks when a module hides itself (the
// battery on a desktop, the VM icon when the container is down).
Rectangle {
  id: root
  default property alias modules: layout.data
  property real moduleSpacing: Theme.fs(2)

  implicitWidth: layout.implicitWidth + Theme.barIslandPadding * 2
  implicitHeight: Theme.barIslandHeight

  // Stadium shape, not Theme.hyprRounding: the capsule is the point of the
  // design, and a theme that sets rounding to 4 would flatten it into the slab
  // the bar used to be.
  radius: height / 2
  color: Theme.bgDeep

  Row {
    id: layout
    anchors.centerIn: parent
    spacing: root.moduleSpacing
  }
}
