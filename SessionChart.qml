import QtQuick
import qs.Commons
import "Brand.js" as Brand

Item {
  id: root
  property var samples: []
  property var spans: []
  property real traceDuration: 1
  property bool waterfall: false
  property color foreground: Color.foreground
  property string hoverText: ""
  property int selected: -1
  readonly property var colors: Brand.kinds
  function tint(kind) { return colors[kind] || colors.unknown }
  function repaint() { plot.requestPaint() }
  onSamplesChanged: repaint()
  onSpansChanged: repaint()
  onTraceDurationChanged: repaint()
  onSelectedChanged: repaint()
  onForegroundChanged: repaint()

  Rectangle {
    anchors.fill: parent
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.25)
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
  }
  Canvas {
    id: plot
    anchors.fill: parent
    anchors.margins: 12
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      var h = height - 20
      ctx.strokeStyle = "#ffffff14"
      ctx.lineWidth = 1
      for (var g = 0; g < 5; g++) {
        ctx.beginPath(); ctx.moveTo(0, g * h / 4); ctx.lineTo(width, g * h / 4); ctx.stroke()
      }
      if (root.waterfall) {
        var count = root.spans.length
        if (!count) return
        var rowH = h / count
        for (var i = 0; i < count; i++) {
          var s = root.spans[i]
          var x = s.start / root.traceDuration * width
          var w = Math.max(3, s.duration / root.traceDuration * width)
          ctx.globalAlpha = root.selected < 0 || root.selected === i ? 1 : 0.45
          ctx.fillStyle = s.error ? Brand.red : root.tint(s.kind)
          ctx.fillRect(x, i * rowH + 2, Math.min(w, width - x), Math.max(2, rowH - 4))
          if (rowH > 13 && w > 55) {
            ctx.fillStyle = "#ffffff"; ctx.font = "10px sans-serif"
            ctx.save(); ctx.beginPath(); ctx.rect(x, i * rowH, w, rowH); ctx.clip()
            ctx.fillText(s.name, x + 5, i * rowH + rowH * 0.7); ctx.restore()
          }
        }
        ctx.globalAlpha = 1
        ctx.fillStyle = root.foreground; ctx.font = "10px sans-serif"
        ctx.fillText("0s", 0, height - 3)
        ctx.textAlign = "right"; ctx.fillText(root.traceDuration.toFixed(1) + "s", width, height - 3); ctx.textAlign = "left"
      } else {
        var maxCount = 1, maxCost = 0.000001
        for (var b of root.samples) {
          var total = 0; for (var k in b.counts) total += b.counts[k]
          maxCount = Math.max(maxCount, total); maxCost = Math.max(maxCost, b.cost)
        }
        var bw = width / Math.max(1, root.samples.length)
        for (var i = 0; i < root.samples.length; i++) {
          var b = root.samples[i], y = h
          ctx.globalAlpha = root.selected < 0 || root.selected === i ? 0.95 : 0.45
          for (var kind in b.counts) {
            var bh = b.counts[kind] / maxCount * (h - 8)
            y -= bh; ctx.fillStyle = root.tint(kind)
            ctx.fillRect(i * bw + 1, y, Math.max(1, bw - 2), bh)
          }
          if (b.errors) { ctx.fillStyle = Brand.red; ctx.beginPath(); ctx.arc(i * bw + bw / 2, Math.max(4, y - 5), 3, 0, Math.PI * 2); ctx.fill() }
        }
        ctx.globalAlpha = 1; ctx.strokeStyle = Brand.yellow; ctx.lineWidth = 2; ctx.beginPath()
        for (var i = 0; i < root.samples.length; i++) {
          var x = (i + 0.5) * bw, y = h - root.samples[i].cost / maxCost * (h - 8)
          if (!i) ctx.moveTo(x, y); else ctx.lineTo(x, y)
        }
        ctx.stroke()
        ctx.fillStyle = root.foreground; ctx.font = "10px sans-serif"
        if (root.samples.length) {
          ctx.fillText(new Date(root.samples[0].time * 1000).toLocaleTimeString(), 0, height - 3)
          ctx.textAlign = "right"; ctx.fillText(new Date(root.samples[root.samples.length - 1].time * 1000).toLocaleTimeString(), width, height - 3); ctx.textAlign = "left"
        }
      }
    }
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onExited: { root.selected = -1; root.hoverText = "" }
      onPositionChanged: function(mouse) {
        if (root.waterfall) {
          var i = Math.floor(mouse.y / (plot.height - 20) * root.spans.length)
          if (i < 0 || i >= root.spans.length) { root.selected = -1; root.hoverText = ""; return }
          root.selected = i
          var s = root.spans[i]
          root.hoverText = s.kind + " · " + s.name + " · " + s.duration.toFixed(3) + "s · depth " + s.depth + (s.error ? " · ERROR" : "")
        } else {
          var i = Math.min(root.samples.length - 1, Math.floor(mouse.x / plot.width * root.samples.length))
          if (i < 0) return
          root.selected = i
          var b = root.samples[i], parts = []
          for (var k in b.counts) parts.push(k + ": " + b.counts[k])
          root.hoverText = new Date(b.time * 1000).toLocaleTimeString() + " · " + parts.join(" / ") + " · $" + b.cost.toFixed(4) + " · " + b.errors + " errors"
        }
      }
    }
  }
}
