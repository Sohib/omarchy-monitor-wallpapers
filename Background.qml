import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root
  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property var editorConfig: ({ version: 1, monitors: ({}) })
  property var editorPreview: ({})
  property var editorErrors: ({})
  property var editorLastGood: ({})
  property var editorUnavailable: ({})
  property int editorRevision: 0
  property string editorPendingMonitor: ""
  property var editorPendingRecord: null
  property bool editorSaveQueued: false
  property var editorPendingConfig: null
  property bool editorConfigLoadedOnce: false
  readonly property string editorConfigPath: home + "/.config/omarchy/background-editor.json"
  readonly property string editorHelper: decodeURIComponent(Qt.resolvedUrl("scripts/editor-io.py").toString()).replace(/^file:\/\//, "")
  readonly property var editorPython: ["/usr/bin/python3", editorHelper]
  property string currentBackground: ""
  property string displayedBackground: ""
  property string incomingBackground: ""
  property string oldBackground: ""
  property bool finishingTransition: false
  property int backgroundVersion: 0
  property int revealStartedVersion: -1
  property int pendingThemeVersion: -1
  property string pendingColorsRaw: ""
  property string pendingShellRaw: ""
  property real revealProgress: 1

  property var hyprOutputs: ({})
  function recordForScreen(screenName) {
    var record = editorPreview[screenName] || editorConfig.monitors[screenName]
    return record || { image: null, mode: "fill", rotation: 0, anchorX: 0.5, anchorY: 0.5, widthPx: 1, heightPx: 1 }
  }
  function backgroundForScreen(screenName, fallback) {
    var record = recordForScreen(screenName)
    if (record.image && editorUnavailable[screenName] === record.image) {
      var lastGood = editorLastGood[screenName]
      return lastGood ? lastGood.path : fallback
    }
    return record.image || fallback
  }
  function noteImageFailure(screenName) {
    var record = recordForScreen(screenName)
    if (!record.image) return
    var unavailable = Object.assign({}, editorUnavailable); unavailable[screenName] = record.image; editorUnavailable = unavailable
    var errors = Object.assign({}, editorErrors); errors[screenName] = "Could not open this image. Choose another image."; editorErrors = errors
    editorRevision++
  }
  function noteImageReady(screenName, source, preparedPath) {
    var record = recordForScreen(screenName)
    if (!record.image || record.image !== source) return
    if (!editorPreview[screenName]) {
      var savedRecord = Object.assign({}, record, { image: preparedPath || source, rotation: preparedPath ? 0 : record.rotation })
      var lastGood = Object.assign({}, editorLastGood); lastGood[screenName] = { path: preparedPath || source, record: savedRecord }; editorLastGood = lastGood
    }
    if (editorUnavailable[screenName] !== source) return
    var unavailable = Object.assign({}, editorUnavailable); delete unavailable[screenName]; editorUnavailable = unavailable
    var errors = Object.assign({}, editorErrors); delete errors[screenName]; editorErrors = errors
    editorRevision++
  }
  function clearUnavailable(screenName, image) {
    if (image && editorUnavailable[screenName] !== image) return
    var unavailable = Object.assign({}, editorUnavailable); delete unavailable[screenName]; editorUnavailable = unavailable
  }
  function outputCanvas(screenName, screen) {
    var output = hyprOutputs[screenName]
    if (output) {
      var scale = Number(output.scale) || 1
      var matchesScreen = Math.abs(Number(screen.width) - output.width / scale) <= 2
        && Math.abs(Number(screen.height) - output.height / scale) <= 2
      return Object.assign({}, output, { physical: output.physical === true && matchesScreen })
    }
    return { width: Number(screen.width), height: Number(screen.height), scale: 1, transform: 0, physical: false }
  }
  function editorState() {
    var monitors = {}
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var s = Quickshell.screens[i]
      var canvas = outputCanvas(String(s.name), s)
      monitors[String(s.name)] = { width: canvas.width, height: canvas.height, x: Number(s.x), y: Number(s.y), scale: canvas.scale, transform: canvas.transform, physical: canvas.physical, focused: !!hyprOutputs[String(s.name)] && hyprOutputs[String(s.name)].focused }
    }
    return JSON.stringify({ config: editorConfig, monitors: monitors, revision: editorRevision, errors: editorErrors, sharedBackground: currentBackground })
  }
  function openEditor() { if (shell) shell.summon("suhayb.background", "") }
  function previewMonitor(name, json) {
    try {
      var record = JSON.parse(json)
      var connectedScreen = null
      for (var i = 0; i < Quickshell.screens.length; i++)
        if (String(Quickshell.screens[i].name) === name) connectedScreen = Quickshell.screens[i]
      if (!connectedScreen) throw new Error("Monitor is disconnected")
      var canvas = outputCanvas(name, connectedScreen)
      if ((record.mode === "original" || record.mode === "custom") && canvas.physical !== true)
        throw new Error("Physical monitor dimensions are unavailable; Original size and Custom size cannot be applied.")
      Model.validateRecord(record, canvas)
      clearUnavailable(name)
      var errors = Object.assign({}, editorErrors); delete errors[name]; editorErrors = errors
      editorPreview = Object.assign({}, editorPreview, (function(){ var o={}; o[name]=record; return o })())
      editorRevision++
      editorPreviewTimer.restart()
    } catch (e) { editorErrors = Object.assign({}, editorErrors, (function(){ var o={}; o[name]=String(e); return o })()); editorRevision++ }
  }
  function cancelEditorPreview() { editorPreview = ({}); editorPreviewTimer.stop(); editorRevision++ }
  function saveMonitor(name, json) {
    if (editorSaveProc.running || editorSaveQueued) return
    try {
      var record = JSON.parse(json)
      var selected = null
      for (var i = 0; i < Quickshell.screens.length; i++)
        if (String(Quickshell.screens[i].name) === name) selected = Quickshell.screens[i]
      if (!selected) throw new Error("Monitor is disconnected")
      var canvas = outputCanvas(name, selected)
      if ((record.mode === "original" || record.mode === "custom") && canvas.physical !== true)
        throw new Error("Physical monitor dimensions are unavailable; Original size and Custom size cannot be applied.")
      var previousErrors = Object.assign({}, editorErrors); delete previousErrors.save; editorErrors = previousErrors
      editorPendingMonitor = name
      editorPendingRecord = Model.validateRecord(record, canvas)
      editorSaveQueued = true
      if (!editorLoadProc.running) editorLoadProc.running = true
    } catch (e) {
      editorErrors = Object.assign({}, editorErrors, (function(){ var o={}; o[name]=String(e); o.save="Could not save wallpaper settings. Try again."; return o })())
      editorRevision++
    }
  }
  function refreshBackground() { if (!readlinkProc.running) readlinkProc.running = true }
  function setBackground(path, instant) { transitionBackground("", path, path, instant, false) }
  function transitionBackground(fromPath, path, finalPath, instant, force) {
    path = String(path || "").trim()
    finalPath = String(finalPath || path).trim()
    if (!path || (!force && finalPath === currentBackground)) return
    if (finalPath !== currentBackground) cancelEditorPreview()
    currentBackground = finalPath
    backgroundVersion += 1
    revealStartedVersion = -1
    revealAnimation.stop()
    finishingTransition = false
    if (instant || !displayedBackground) {
      oldBackground = ""; incomingBackground = ""; displayedBackground = path; revealProgress = 1; return
    }
    oldBackground = fromPath || displayedBackground
    revealProgress = 0
    incomingBackground = path
  }


  function setPendingTheme(colorsB64, shellB64) {
    pendingColorsRaw = Util.decodeBase64(colorsB64)
    pendingShellRaw = Util.decodeBase64(shellB64)
    pendingThemeVersion = backgroundVersion
    pendingThemeFallbackTimer.restart()
  }

  function applyPendingTheme() {
    // Background polling can advance backgroundVersion while a theme switch is
    // pending; the latest theme payload should still apply.
    if (pendingThemeVersion < 0) return
    pendingThemeFallbackTimer.stop()
    Commons.Color.loadColors(pendingColorsRaw)
    // Color.loadShell also refreshes Style so the type scale flips with the
    // background reveal instead of waiting for a separate reload path.
    Commons.Color.loadShell(pendingShellRaw)
    Style.scheduleRefresh()
    pendingThemeVersion = -1
    pendingColorsRaw = ""
    pendingShellRaw = ""
  }

  function transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64) {
    cancelEditorPreview()
    transitionBackground(fromPath, path, finalPath, false, true)
    setPendingTheme(colorsB64, shellB64)
    if (!incomingBackground || revealProgress >= 1) applyPendingTheme()
  }

  function startReveal(panel) {
    if (!incomingBackground) return
    panel.maskReady = true
    if (revealStartedVersion === backgroundVersion) return
    revealStartedVersion = backgroundVersion
    applyPendingTheme()
    revealAnimation.restart()
  }

  function openSelector() { openEditor() }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-c", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"]
    onExited: root.refreshBackground()
  }

  Process {
    id: editorLoadProc
    command: root.editorPython.concat(["read"])
    stdout: StdioCollector { onStreamFinished: {
      try {
        var raw = String(text || "").trim()
        if (!raw) throw new Error("Settings reader returned no data.")
        var parsed = JSON.parse(raw)
        var latest = Model.normalizeConfig(parsed)
        if (root.editorErrors.settings) {
          var recoveredErrors = Object.assign({}, root.editorErrors)
          delete recoveredErrors.settings
          root.editorErrors = recoveredErrors
          root.editorRevision++
        }
        if (parsed.migrationNotice) root.editorErrors = Object.assign({}, root.editorErrors, { migration: parsed.migrationNotice })
        else if (root.editorErrors.migration) { var errors = Object.assign({}, root.editorErrors); delete errors.migration; root.editorErrors = errors }
        if (JSON.stringify(latest) !== JSON.stringify(root.editorConfig)) {
          if (root.editorConfigLoadedOnce && !editorSaveProc.running) {
            root.cancelEditorPreview()
            var errors = Object.assign({}, root.editorErrors, { external: "Saved settings changed. Reopen the editor to reload." })
            if (root.editorSaveQueued) {
              errors.save = "Could not save wallpaper settings. Try again."
              root.editorSaveQueued = false
            }
            root.editorErrors = errors
            root.editorRevision++
          }
          if (!root.editorSaveQueued) root.editorConfig = latest
        }
        root.editorConfigLoadedOnce = true
        if (root.editorSaveQueued) {
          var next = JSON.parse(JSON.stringify(latest))
          next.monitors[root.editorPendingMonitor] = root.editorPendingRecord
          root.editorPendingConfig = next
          root.editorSaveQueued = false
          editorSaveProc.command = root.editorPython.concat(["write", JSON.stringify(next)])
          editorSaveProc.running = true
        }
      } catch (e) {
        var saveFailed = root.editorSaveQueued
        var errors = Object.assign({}, root.editorErrors, { settings: String(e) })
        if (saveFailed) errors.save = "Could not save wallpaper settings. Try again."
        root.editorErrors = errors
        root.editorSaveQueued = false
        root.editorRevision++
      }
    } }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var errors = Object.assign({}, root.editorErrors, { settings: "Settings file refused; keeping the last valid settings." })
        if (root.editorSaveQueued) errors.save = "Could not save wallpaper settings. Try again."
        root.editorErrors = errors
        root.editorSaveQueued = false
        root.editorRevision++
      }
    }
  }

  FileView {
    path: root.editorConfigPath
    watchChanges: true
    printErrors: false
    onFileChanged: if (!editorLoadProc.running) editorLoadProc.running = true
  }

  Process {
    id: editorSaveProc
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.editorConfig = root.editorPendingConfig
        root.editorPreview = ({})
        editorPreviewTimer.stop()
        clearUnavailable(root.editorPendingMonitor, root.editorPendingRecord.image)
        root.editorErrors = ({})
      } else root.editorErrors = Object.assign({}, root.editorErrors, ({ save: "Could not save wallpaper settings. Try again." }))
      root.editorRevision++
    }
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: {
        const path = String(text || "").trim()
        root.setBackground(path, false)
      }
    }
  }
  Process {
    id: monitorMetadataProc
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector { onStreamFinished: {
      try {
        var list = JSON.parse(text)
        var output = {}
        for (var i = 0; i < list.length; i++) {
          var item = list[i]
          var oddTransform = [1, 3, 5, 7].indexOf(Number(item.transform)) >= 0
          output[String(item.name)] = {
            width: Number(oddTransform ? item.height : item.width),
            height: Number(oddTransform ? item.width : item.height),
            scale: Number(item.scale), transform: Number(item.transform), physical: Number(item.width) > 0 && Number(item.height) > 0,
            x: Number(item.x), y: Number(item.y), focused: item.focused === true
          }
        }
        var topology = {}
        for (var name in output) {
          var item = output[name]
          topology[name] = { width: item.width, height: item.height, scale: item.scale, transform: item.transform, x: item.x, y: item.y }
        }
        var previousTopology = {}
        for (var name in root.hyprOutputs) {
          var previous = root.hyprOutputs[name]
          previousTopology[name] = { width: previous.width, height: previous.height, scale: previous.scale, transform: previous.transform, x: previous.x, y: previous.y }
        }
        var changed = JSON.stringify(topology) !== JSON.stringify(previousTopology)
        root.hyprOutputs = output
        if (changed) root.cancelEditorPreview()
      } catch (e) {}
    } }
  }
  Timer {
    interval: 3000
    repeat: true
    running: true
    onTriggered: if (!monitorMetadataProc.running) monitorMetadataProc.running = true
  }

  IpcHandler {
    target: "background"

    function refresh(): void {
      root.refreshBackground()
    }

    function set(path: string): void {
      root.setBackground(path, false)
    }

    function setInstant(path: string): void {
      root.setBackground(path, true)
    }

    function transition(fromPath: string, path: string): void {
      root.transitionBackground(fromPath, path, path, false, false)
    }

    function themeTransition(fromPath: string, path: string, finalPath: string, colorsB64: string, shellB64: string): void {
      root.transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64)
    }
    function editorState(): string { return root.editorState() }
    function previewMonitor(monitor: string, recordJson: string): void { root.previewMonitor(monitor, recordJson) }
    function cancelPreview(): void { root.cancelEditorPreview() }
    function saveMonitor(monitor: string, recordJson: string): void { root.saveMonitor(monitor, recordJson) }
    function openEditor(): void { root.openEditor() }
  }
  Timer {
    id: editorPreviewTimer
    interval: 20000
    repeat: false
    onTriggered: root.cancelEditorPreview()
  }


  Timer {
    id: pendingThemeFallbackTimer
    interval: 300
    repeat: false
    onTriggered: root.applyPendingTheme()
  }

  NumberAnimation {
    id: revealAnimation
    target: root
    property: "revealProgress"
    from: 0
    to: 1
    duration: 420
    easing.type: Easing.InOutCubic
    onFinished: {
      if (root.incomingBackground) {
        root.finishingTransition = true
        root.displayedBackground = root.currentBackground || root.incomingBackground
      }
      root.revealProgress = 1
    }
  }

  Component.onCompleted: {
    refreshBackground()
    editorLoadProc.running = true
    monitorMetadataProc.running = true
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: !remapGuard.remapping
      anchors { top: true; bottom: true; left: true; right: true }

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }
      color: "transparent"
      // Keep render updates enabled. The background layer has been observed to
      // lose its committed buffer while parked with updatesEnabled=false,
      // leaving a black desktop until omarchy-shell is restarted. The wallpaper
      // itself is static, so this favors correctness over a small render-loop
      // optimization.
      updatesEnabled: true

      property bool maskReady: false
      readonly property string monitorName: String(modelData.name || "")

      readonly property var currentWallpaperRecord: root.recordForScreen(monitorName)
      readonly property bool usingLastGood: currentWallpaperRecord.image && root.editorUnavailable[monitorName] === currentWallpaperRecord.image && !!root.editorLastGood[monitorName]
      readonly property var wallpaperRecord: usingLastGood ? root.editorLastGood[monitorName].record : currentWallpaperRecord
      readonly property var canvas: root.outputCanvas(monitorName, modelData)
      readonly property string wallpaperPath: root.backgroundForScreen(monitorName, root.displayedBackground)
      readonly property string oldWallpaperPath: root.backgroundForScreen(monitorName, root.oldBackground)
      readonly property string incomingWallpaperPath: root.backgroundForScreen(monitorName, root.incomingBackground)
      readonly property bool wallpaperUnavailable: !!currentWallpaperRecord.image && root.editorUnavailable[monitorName] === currentWallpaperRecord.image && !usingLastGood
      readonly property bool needsPreparedImage: !usingLastGood && (wallpaperRecord.image || wallpaperRecord.rotation !== 0)

      function maybeStartReveal() {
        if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
        if (!incomingFrame.imageReady) return
        Qt.callLater(function() {
          if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
          if (!incomingFrame.imageReady) return
          root.startReveal(panel)
        })
      }
      function maybeFinishTransition() {
        if (!root.finishingTransition || !base.imageReady) return
        root.incomingBackground = ""
        root.oldBackground = ""
        root.finishingTransition = false
      }

      WlrLayershell.namespace: "omarchy-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      WallpaperFrame {
        id: base
        anchors.fill: parent
        originalSource: panel.needsPreparedImage && !panel.wallpaperUnavailable ? panel.wallpaperPath : ""
        source: panel.needsPreparedImage && !panel.wallpaperUnavailable ? "" : panel.wallpaperPath
        allowRawFallback: !panel.wallpaperRecord.image
        leaseOwner: "service-" + panel.monitorName + "-base"
        rotation: panel.wallpaperRecord.rotation
        canvasWidth: panel.canvas.width
        canvasHeight: panel.canvas.height
        record: panel.wallpaperRecord
        asynchronous: true
        onReady: {
          if (!panel.usingLastGood && panel.currentWallpaperRecord.image && panel.wallpaperPath === panel.currentWallpaperRecord.image)
            root.noteImageReady(panel.monitorName, panel.currentWallpaperRecord.image, base.preparedPath)
          if (root.finishingTransition) Qt.callLater(panel.maybeFinishTransition)
        }
        onFailed: root.noteImageFailure(panel.monitorName)
      }

      WallpaperFrame {
        id: oldFrame
        anchors.fill: parent
        originalSource: panel.needsPreparedImage && !panel.wallpaperUnavailable ? panel.oldWallpaperPath : ""
        source: panel.needsPreparedImage && !panel.wallpaperUnavailable ? "" : panel.oldWallpaperPath
        allowRawFallback: !panel.wallpaperRecord.image
        leaseOwner: "service-" + panel.monitorName + "-old"
        rotation: panel.wallpaperRecord.rotation
        canvasWidth: panel.canvas.width
        canvasHeight: panel.canvas.height
        record: panel.wallpaperRecord
        asynchronous: true
        visible: root.oldBackground !== "" && root.revealProgress < 1
        onReady: panel.maybeStartReveal()
      }

      Item {
        id: incomingLayer
        anchors.fill: parent
        visible: root.incomingBackground !== "" && incomingFrame.imageReady && (root.revealProgress >= 1 || panel.maskReady)
        layer.enabled: root.incomingBackground !== "" && root.revealProgress < 1
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: revealMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 0.02
        }

        WallpaperFrame {
          id: incomingFrame
          anchors.fill: parent
          originalSource: panel.needsPreparedImage && !panel.wallpaperUnavailable ? panel.incomingWallpaperPath : ""
          source: panel.needsPreparedImage && !panel.wallpaperUnavailable ? "" : panel.incomingWallpaperPath
          allowRawFallback: !panel.wallpaperRecord.image
          leaseOwner: "service-" + panel.monitorName + "-incoming"
          rotation: panel.wallpaperRecord.rotation
          canvasWidth: panel.canvas.width
          canvasHeight: panel.canvas.height
          record: panel.wallpaperRecord
          asynchronous: true
          onReady: Qt.callLater(panel.maybeStartReveal)
          onFailed: {
            if (panel.wallpaperRecord.image) root.noteImageFailure(panel.monitorName)
            else if (root.incomingBackground) {
              root.incomingBackground = ""
              root.oldBackground = ""
              root.revealProgress = 1
              root.finishingTransition = false
            }
          }
        }
      }

      Item {
        id: revealMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        readonly property real slant: -0.18
        readonly property real centerTop: width / 2 - slant * height / 2
        readonly property real centerBottom: width / 2 + slant * height / 2
        readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
        readonly property real spread: reach * root.revealProgress

        Shape {
          anchors.fill: parent
          antialiasing: true
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: "white"
            strokeColor: "transparent"
            startX: revealMask.centerTop - revealMask.spread; startY: 0
            PathLine { x: revealMask.centerTop + revealMask.spread; y: 0 }
            PathLine { x: revealMask.centerBottom + revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerBottom - revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerTop - revealMask.spread; y: 0 }
          }
        }
      }

      Connections {
        target: root
        function onIncomingBackgroundChanged() {
          panel.maskReady = false
          panel.maybeStartReveal()
        }
        function onFinishingTransitionChanged() {
          if (root.finishingTransition) Qt.callLater(panel.maybeFinishTransition)
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.openThemeSwitcher()
          else root.openSelector()
          mouse.accepted = true
        }
      }
    }
  }
}
