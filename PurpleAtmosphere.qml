import QtQuick
import "Brand.js" as Brand

Rectangle {
  id: root
  property bool animate: false
  radius: 12
  color: "#101010"
  border.color: Brand.purple3
  border.width: 1
  clip: true

  ShaderEffect {
    id: pixels
    anchors.fill: parent
    // Lapdog PixelBlast motion with official brand Purple 3 (#8000FF):
    // scale/density 1.5, jitter .5, speed .9, edge fade .25.
    property vector2d uResolution: Qt.vector2d(width, height)
    property real uTime: 650
    property color uColor: Brand.purple3
    property vector4d uClick: Qt.vector4d(0, 0, 0, 0)
    property vector2d uPointer: Qt.vector2d(-10000, -10000)
    property real uPointerAge: -1000
    fragmentShader: Qt.resolvedUrl("pixelblast.frag.qsb")
    NumberAnimation on uTime {
      from: 650
      to: 100650
      duration: 111111111
      running: root.animate
      loops: Animation.Infinite
    }
  }
  TapHandler {
    onTapped: function(eventPoint) {
      pixels.uClick = Qt.vector4d(eventPoint.position.x, eventPoint.position.y, pixels.uTime, 1)
    }
  }
}
