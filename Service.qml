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
  //
  // lastAppliedStamp advances only on a SUCCESSFUL apply, so the 3s poll
  // naturally retries a failed or raced apply; failedStamp caps that retry
  // at 3 attempts per stamp so broken input cannot become a crash loop.
  property string lastSeenStamp: ""
  property string lastAppliedStamp: ""
  property string failedStamp: ""
  property int failCount: 0
  property string pendingStamp: ""

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
    if (stamp === "") return
    var first = lastSeenStamp === ""
    lastSeenStamp = stamp
    if (applyProcess.running) return
    if (stamp === lastAppliedStamp) return
    if (stamp === failedStamp && failCount >= 3) return
    // autoApply Off means exactly that: mark the stamp handled and wait for
    // the user. The one exception is a genuinely fresh install (no state
    // yet), where enabling the plugin IS the request to theme the apps.
    var freshInstall = state === null
    if (!autoApply && !(first && freshInstall)) {
      lastAppliedStamp = stamp
      return
    }
    // The automatic first apply skips app restarts: it can fire before the
    // bar widget has pushed the user's restartApps setting.
    applyNow(first)
  }

  // ------------------------------------------------------------------ apply
  Process {
    id: applyProcess
    running: false
    command: [root.pluginDir + "/bin/accord-apply"]
    // Quickshell's Process never emits exited on a FailedToStart spawn
    // error, so the applying flag is cleared from running itself.
    onRunningChanged: if (!running) root.applying = false
    onExited: function(exitCode, exitStatus) {
      root.applying = false
      if (exitCode === 0) {
        root.lastAppliedStamp = root.pendingStamp
        root.failedStamp = ""
        root.failCount = 0
      } else if (root.failedStamp === root.pendingStamp) {
        root.failCount++
      } else {
        root.failedStamp = root.pendingStamp
        root.failCount = 1
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.lastError = text.trim()
        if (root.lastError !== "") console.warn("accord", root.lastError)
      }
    }
  }

  // A wedged child would otherwise block every future apply forever; the
  // Process type has no timeout of its own.
  Timer {
    interval: 30000
    running: applyProcess.running
    onTriggered: applyProcess.signal(9)
  }
  Timer {
    interval: 10000
    running: probeProcess.running
    onTriggered: probeProcess.signal(9)
  }

  function applyNow(firstRun) {
    if (applyProcess.running) return
    var cmd = [root.pluginDir + "/bin/accord-apply"]
    if (!restartApps || firstRun === true) cmd.push("--no-restart")
    pendingStamp = lastSeenStamp
    applyProcess.command = cmd
    root.applying = true
    applyProcess.running = true
  }
}
