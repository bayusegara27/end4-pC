import QtQuick

Canvas {
    id: root
    property list<real> dataPoints: []
    property color lineColor: "#60a5fa"
    property color fillColor: Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.15)
    property real lineWidth: 1.5
    property real maxValue: 1.0

    implicitWidth: 80
    implicitHeight: 24

    onDataPointsChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onFillColorChanged: requestPaint()
    onLineWidthChanged: requestPaint()
    onMaxValueChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var w = width
        var h = height
        ctx.clearRect(0, 0, w, h)
        var pts = dataPoints
        if (!pts || pts.length === 0) return
        if (pts.length === 1) pts = [pts[0], pts[0]]

        var max = maxValue > 0 ? maxValue : 1.0
        var stepX = w / (pts.length - 1)
        var pad = 2

        // Build path
        ctx.beginPath()
        var y0 = (h - pad) - (Math.max(0, Math.min(max, Number(pts[0]) || 0)) / max) * (h - pad * 2)
        ctx.moveTo(0, y0)
        for (var i = 1; i < pts.length; i++) {
            var x = i * stepX
            var y = (h - pad) - (Math.max(0, Math.min(max, Number(pts[i]) || 0)) / max) * (h - pad * 2)
            ctx.lineTo(x, y)
        }

        // Stroke
        ctx.strokeStyle = lineColor
        ctx.lineWidth = lineWidth
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.stroke()

        // Fill area under curve with vertical gradient
        ctx.lineTo(w, h)
        ctx.lineTo(0, h)
        ctx.closePath()
        var grad = ctx.createLinearGradient(0, 0, 0, h)
        grad.addColorStop(0, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.35))
        grad.addColorStop(1, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.0))
        ctx.fillStyle = grad
        ctx.fill()
    }
}
