import QtQuick
import Quickshell
import Quickshell.Io

// Accord service: keeps GTK/Qt palettes in step with the Omarchy theme.
// All generation lives behind bin/accord-apply (plain python, testable
// without the shell); this file only notices theme changes, schedules the
// helper, and exposes state.json to the bar widget and panel.
Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null
  // Services receive no settings injection; the bar widget pushes its
  // settings object here so autoApply/restartApps have one source of truth.
  property var settings: ({})

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/accord"
  readonly property string themeDir: home + "/.local/state/omarchy/current/theme"
  readonly property string pluginDir: manifest && manifest.__sourceDir
    ? manifest.__sourceDir
    : home + "/.config/omarchy/plugins/io.github.vonsensey.accord"

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property bool autoApply: String(setting("autoApply", "On")).toLowerCase() !== "off"
  readonly property bool restartApps: String(setting("restartApps", "On")).toLowerCase() !== "off"

  // Parsed state.json, written by accord-apply. Null until the first apply.
  property var state: null
  property bool applying: false
  property string lastError: ""

  readonly property string themeName: state && state.theme ? String(state.theme) : ""
  readonly property string mode: state && state.mode ? String(state.mode) : ""
  readonly property var palette: state && state.palette ? state.palette : null

  FileView {
    path: root.stateDir + "/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseState(text())
    onLoadFailed: root.state = null
  }

  function parseState(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      root.state = parsed && typeof parsed === "object" ? parsed : null
    } catch (e) {
      console.warn("accord", "Ignoring bad state.json", e)
      root.state = null
    }
  }

  // ------------------------------------------------- theme change detection
  // omarchy-theme-set swaps the current/theme SYMLINK, which a watcher on
  // the resolved file can miss entirely - so poll the identity instead:
  // resolved path + colors.toml mtime, compared as one string.
  property string themeStamp: ""

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.probeTheme()
  }

  Process {
    id: probeProcess
    running: false
    command: ["sh", "-c",
      'p=$(readlink -f -- "$1") || exit 0; printf "%s %s\\n" "$p" "$(stat -c %Y -- "$p/colors.toml" 2>/dev/null)"',
      "-", root.themeDir]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onProbe(text.trim())
    }
  }

  function probeTheme() {
    if (!probeProcess.running) probeProcess.running = true
  }

  function onProbe(stamp) {
    if (stamp === "" || stamp === themeStamp) return
    var first = themeStamp === ""
    themeStamp = stamp
    // First probe after (re)load: apply so a fresh enable is themed at once.
    // Later probes are real theme switches, gated by the autoApply setting.
    if (first || autoApply) runApply()
  }

  // ------------------------------------------------------------------ apply
  Process {
    id: applyProcess
    running: false
    command: [root.pluginDir + "/bin/accord-apply"]
    onExited: root.applying = false

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.lastError = text.trim()
        if (root.lastError !== "") console.warn("accord", root.lastError)
      }
    }
  }

  function runApply() {
    if (applyProcess.running) return
    var cmd = [root.pluginDir + "/bin/accord-apply"]
    if (!restartApps) cmd.push("--no-restart")
    applyProcess.command = cmd
    root.applying = true
    applyProcess.running = true
  }

  function applyNow() { runApply() }
}
