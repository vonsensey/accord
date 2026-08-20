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

  Rectangle {
    id: dot
    width: Style.space(12)
    height: width
    radius: width / 2
    anchors.centerIn: parent
    color: root.accentColor
    border.width: Math.max(1, Style.spaceReal(1))
    border.color: root.bar ? root.bar.barForeground : Color.foreground
    // Before the first apply the dot is hollow: enabled but not yet run.
    opacity: root.applied ? 1.0 : 0.45

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
