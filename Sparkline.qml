import QtQuick
import qs.Commons

// A filled line graph of recent samples. Oldest on the left, newest on the
// right; `ceiling` pins the top of the scale (100 for percentages) so the
// line means the same thing from one frame to the next.
Canvas {
  id: root

  property var values: []
  property color lineColor: Color.accent
  property real ceiling: 100

  antialiasing: true

  onValuesChanged: requestPaint()
  onLineColorChanged: requestPaint()
  onCeilingChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)

    var points = Array.isArray(values) ? values : []
    if (points.length === 0 || width <= 0 || height <= 0) return

    // An explicit ceiling keeps the scale honest; without one, grow to fit
    // the tallest sample so a flat-but-small series is still readable.
    var top = Number(ceiling)
    if (!isFinite(top) || top <= 0) {
      top = 1
      for (var i = 0; i < points.length; i++) {
        var v = Number(points[i])
        if (isFinite(v)) top = Math.max(top, v)
      }
      top *= 1.12
    }

    var step = points.length > 1 ? width / (points.length - 1) : width
    var yFor = function(value) {
      var n = Math.max(0, Math.min(1, Number(value || 0) / top))
      return height - n * Math.max(1, height - 1)
    }

    ctx.beginPath()
    ctx.moveTo(0, height)
    for (var j = 0; j < points.length; j++)
      ctx.lineTo(points.length > 1 ? j * step : width, yFor(points[j]))
    ctx.lineTo(width, height)
    ctx.closePath()
    ctx.fillStyle = Qt.rgba(root.lineColor.r, root.lineColor.g, root.lineColor.b, 0.14)
    ctx.fill()

    ctx.beginPath()
    for (var k = 0; k < points.length; k++) {
      var x = points.length > 1 ? k * step : width
      var y = yFor(points[k])
      if (k === 0) ctx.moveTo(x, y)
      else ctx.lineTo(x, y)
    }
    ctx.strokeStyle = root.lineColor
    ctx.lineWidth = 1.5
    ctx.lineJoin = "round"
    ctx.lineCap = "round"
    ctx.stroke()
  }
}
