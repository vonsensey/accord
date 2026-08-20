import QtQuick
import qs.Ui
import qs.Commons

// Accord bar widget: a dot wearing the CURRENT accent color, read back from
// what accord-apply actually wrote - the widget itself is live proof the
// bridge ran. Click opens the palette panel; right click re-applies now.
BarWidget {
  id: root
  moduleName: "io.github.vonsensey.accord"

  readonly property string pluginId: "io.github.vonsensey.accord"
  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor(pluginId) : null

  function pushSettings() {
    if (svc) svc.settings = settings
  }
  Component.onCompleted: pushSettings()
  onSettingsChanged: pushSettings()
  onSvcChanged: pushSettings()

  readonly property var palette: svc ? svc.palette : null
  readonly property color accentColor: palette && palette.accent
    ? palette.accent
    : (bar ? bar.barForeground : Color.foreground)
  readonly property bool applied: palette !== null

  implicitWidth: root.vertical ? barSize : dot.width + Style.space(14)
  implicitHeight: root.vertical ? dot.height + Style.space(14) : barSize

  // The palette wheel: six segments painted from the palette Accord actually
  // wrote to disk - the icon IS the feature, not a generic dot. Hollow until
  // the first apply (enabled but not yet run).
  Item {
    id: dot
    width: Style.space(12)
    height: width
    anchors.centerIn: parent
    opacity: root.applied ? 1.0 : 0.45

    // Hue order reads as a color wheel; any key an older state.json lacks
    // falls back to the accent so the wheel never shows holes.
    readonly property var wheel: {
      var p = root.palette
      var a = String(root.accentColor)
      if (!p) return []
      return [p.red || a, p.yellow || a, p.green || a,
              p.cyan || a, p.blue || a, p.magenta || a]
    }
    onWheelChanged: canvas.requestPaint()

    Canvas {
      id: canvas
      anchors.fill: parent
      visible: root.applied
      antialiasing: true
      Component.onCompleted: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var colors = dot.wheel
        if (!colors.length) return
        var cx = width / 2, cy = height / 2, r = Math.min(cx, cy)
        for (var i = 0; i < colors.length; i++) {
          ctx.beginPath()
          ctx.moveTo(cx, cy)
          ctx.arc(cx, cy, r,
                  (i / colors.length) * 2 * Math.PI - Math.PI / 2,
                  ((i + 1) / colors.length) * 2 * Math.PI - Math.PI / 2)
          ctx.closePath()
          ctx.fillStyle = String(colors[i])
          ctx.fill()
        }
      }
    }

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: "transparent"
      border.width: Math.max(1, Style.spaceReal(1))
      border.color: root.bar ? root.bar.barForeground : Color.foreground
    }

    SequentialAnimation on scale {
      running: root.svc ? root.svc.applying : false
      loops: Animation.Infinite
      NumberAnimation { from: 1.0; to: 0.72; duration: 350; easing.type: Easing.InOutQuad }
      NumberAnimation { from: 0.72; to: 1.0; duration: 350; easing.type: Easing.InOutQuad }
    }
  }

  function tooltipText() {
    if (!root.svc || !root.svc.state) return "Accord - not applied yet. Click to open."
    var s = root.svc.state
    var line = "Accord - GTK & Qt follow " + (s.theme || "the theme")
    var pending = s.restarts && s.restarts.pending ? s.restarts.pending : []
    if (pending.length > 0) line += "  (restart pending: " + pending.join(", ") + ")"
    return line
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        if (root.svc) root.svc.applyNow()
      } else if (root.bar && root.bar.shell) {
        root.bar.shell.toggle(root.pluginId, "{}")
      }
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltipText())
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
