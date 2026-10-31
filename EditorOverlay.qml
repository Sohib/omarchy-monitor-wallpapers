import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root
  property bool opened: false
  property bool pickerHidden: false
  property var screens: Quickshell.screens || []
  property var connected: ({})
  property bool monitorManuallySelected: false
  property int serviceRevision: 0
  property int saveRevision: -1
  property string saveMonitor: ""
  property var saveRecord: null
  property bool savePending: false
  property string selectedMonitor: screens.length ? String(screens[0].name || "") : ""
  property string imagePath: ""
  property var drafts: ({})
  property string folder: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/backgrounds"
  property var imageFiles: []
  readonly property int readableImageCount: imageFiles.filter(function(path) { return !root.unreadable[path] }).length
  property var config: ({ version: 1, monitors: ({}) })
  property var baselineConfig: null
  property bool settingsConflict: false
  property bool gotInitialState: false
  property var prepared: ({ path: "", width: 0, height: 0 })
  property string sharedImage: ""
  property string preparedSource: ""
  property int preparedRotation: -1
  readonly property bool selectionReady: imagePath !== "" && preparedSource === imagePath
    && preparedRotation === rotation && !prepareProcess.running && !prepareQueued
  property int preparingRotation: 0
  property string preparingPath: ""
  property string listingFolder: ""
  property bool prepareQueued: false
  property bool listQueued: false
  property var unreadable: ({})
  property var folderByMonitor: ({})
  property string errorText: ""
  property var serviceErrors: ({})
  property int rotation: 0
  property string mode: "fill"
  property real anchorX: 0.5
  property real anchorY: 0.5
  property int widthPx: 0
  property int heightPx: 0
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("scripts/editor-io.py").toString()).replace(/^file:\/\//, "")
  readonly property var recommendation: selectionReady && prepared.width > 0 && canvas().width > 0
    ? Model.recommend(prepared.width, prepared.height, canvas().width, canvas().height, 0) : null
  readonly property bool distorted: selectionReady && prepared.width > 0
    && ((mode === "stretch" && Math.abs(canvas().width / canvas().height - prepared.width / prepared.height) > 0.001)
    || (mode === "custom" && Math.abs(widthPx / heightPx - prepared.width / prepared.height) > 0.001))
  readonly property var commandBase: ["/usr/bin/python3", helper]
  property int previewSeconds: 0

  property string focusMonitor: ""
  function open() { drafts = ({}); gotInitialState = false; baselineConfig = null; settingsConflict = false; errorText = ""; monitorManuallySelected = false; focusMonitor = ""; opened = true; loadState(); refreshImages(); if (!focusProcess.running) focusProcess.running = true }
  function selectMonitor(name) { storeDraft(); selectedMonitor = String(name); monitorManuallySelected = true; loadDraft() }
  function loadState() { if (!stateProcess.running) stateProcess.running = true }
  function endPreview() { if (!cancelProcess.running) cancelProcess.running = true; previewTimer.stop(); previewSeconds = 0 }
  function close() { endPreview(); opened = false; pickerHidden = false }
  Component.onDestruction: close()
  function canvas() { return connected[selectedMonitor] || { width: 0, height: 0 } }
  function overviewRect(name) {
    var keys = Object.keys(connected)
    if (!keys.length) return { x: 0, y: 0, width: 0, height: 0 }
    var minX = 1e20, minY = 1e20, maxX = -1e20, maxY = -1e20
    for (var i = 0; i < keys.length; i++) {
      var out = connected[keys[i]], scale = Number(out.scale) || 1
      var x = Number(out.x) || 0, y = Number(out.y) || 0
      minX = Math.min(minX, x); minY = Math.min(minY, y)
      maxX = Math.max(maxX, x + Number(out.width) / scale)
      maxY = Math.max(maxY, y + Number(out.height) / scale)
    }
    var factor = Math.min(700 / Math.max(1, maxX - minX), 68 / Math.max(1, maxY - minY))
    var output = connected[name], outputScale = Number(output.scale) || 1
    return { x: 8 + ((Number(output.x) || 0) - minX) * factor,
      y: 4 + ((Number(output.y) || 0) - minY) * factor,
      width: Math.max(40, Number(output.width) / outputScale * factor),
      height: Math.max(28, Number(output.height) / outputScale * factor) }
  }
  function storeDraft() {
    var next = JSON.parse(JSON.stringify(drafts))
    next[selectedMonitor] = record()
    drafts = next
    var folders = Object.assign({}, folderByMonitor); folders[selectedMonitor] = folder; folderByMonitor = folders
  }
  function loadDraft() {
    var r = drafts[selectedMonitor] || config.monitors[selectedMonitor] || { image: null, mode: "fill", rotation: 0, anchorX: 0.5, anchorY: 0.5, widthPx: canvas().width, heightPx: canvas().height }
    imagePath = r.image || ""
    mode = r.mode
    rotation = r.rotation
    anchorX = r.anchorX
    anchorY = r.anchorY
    widthPx = r.widthPx || canvas().width
    heightPx = r.heightPx || canvas().height
    var defaultFolder = Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/backgrounds"
    folder = folderByMonitor[selectedMonitor] || defaultFolder
    refreshImages()
    prepareSelection()
  }
  function pickerResult(value) {
    var path = String(value || "")
    if (path.slice(-2) === "\r\n") return path.slice(0, -2)
    if (path.slice(-1) === "\n") return path.slice(0, -1)
    return path
  }
  function refreshImages() {
    if (listProcess.running) { listQueued = true; return }
    listQueued = false
    listingFolder = folder
    listProcess.command = commandBase.concat(["images", listingFolder])
    listProcess.running = true
  }
  function chooseFolder(path) {
    folder = path
    var folders = Object.assign({}, folderByMonitor); folders[selectedMonitor] = path; folderByMonitor = folders
    refreshImages()
  }
  function prepareSelection() {
    preparedRotation = -1
    if (!imagePath) { prepared = { path: "", width: 0, height: 0 }; preparedSource = ""; return }
    if (prepareProcess.running) { prepareQueued = true; return }
    prepareQueued = false
    preparingPath = imagePath
    preparingRotation = rotation
    prepareProcess.command = commandBase.concat(["prepare", preparingPath, String(preparingRotation)])
    prepareProcess.running = true
  }
  function selectImage(path) {
    imagePath = path
    var parentFolder = path.substring(0, path.lastIndexOf("/"))
    if (parentFolder && parentFolder !== folder) chooseFolder(parentFolder)
    prepareSelection()
  }
  function navigate(step) {
    if (readableImageCount < 2) return
    var start = imageFiles.indexOf(imagePath)
    for (var offset = 1; offset <= imageFiles.length; offset++) {
      var candidate = imageFiles[(start + step * offset + imageFiles.length * 2) % imageFiles.length]
      if (!unreadable[candidate]) { selectImage(candidate); return }
    }
    errorText = "No readable images in this folder. Choose another folder."
  }
  function record() { return { image: imagePath || null, mode: mode, rotation: rotation, anchorX: anchorX, anchorY: anchorY, widthPx: widthPx || canvas().width, heightPx: heightPx || canvas().height } }
  function preview() {
    previewProcess.command = ["omarchy-shell", "background", "previewMonitor", selectedMonitor, JSON.stringify(record())]
    previewProcess.running = true
    previewSeconds = 20
    previewTimer.restart()
  }
  function apply() {
    if (savePending || settingsConflict || !canvas().width || !canvas().height) return
    savePending = true
    saveRevision = serviceRevision
    saveMonitor = selectedMonitor
    saveRecord = record()
    saveProcess.command = ["omarchy-shell", "background", "saveMonitor", saveMonitor, JSON.stringify(saveRecord)]
    saveProcess.running = true
  }

  Process {
    id: focusProcess
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector { onStreamFinished: {
      try {
        var monitors = JSON.parse(text)
        for (var i = 0; i < monitors.length; i++) {
          if (monitors[i].focused) {
            root.focusMonitor = String(monitors[i].name || "")
            if (root.opened && !root.monitorManuallySelected && root.connected[root.focusMonitor] && root.selectedMonitor !== root.focusMonitor) {
              if (root.gotInitialState) root.storeDraft()
              root.selectedMonitor = root.focusMonitor
              if (root.gotInitialState) root.loadDraft()
            }
            break
          }
        }
      } catch (e) {}
    } }
  }
  Process {
    id: stateProcess
    command: ["omarchy-shell", "background", "editorState"]
    stdout: StdioCollector { onStreamFinished: {
      try {
        var state = JSON.parse(text)
        var incoming = Model.normalizeConfig(state.config)
        root.connected = state.monitors || ({})
        root.serviceErrors = state.errors || ({})
        root.sharedImage = String(state.sharedBackground || "")
        root.serviceRevision = Number(state.revision || 0)
        if (!root.gotInitialState) {
          root.config = incoming
          root.baselineConfig = Util.cloneJson(incoming)
          root.errorText = state.errors && (state.errors.settings || state.errors.migration || state.errors.save) || ""
          var outputNames = Object.keys(root.connected).sort()
          if (!root.monitorManuallySelected) {
            var focused = root.focusMonitor || ""
            if (!focused) for (var i = 0; i < outputNames.length; i++) if (root.connected[outputNames[i]].focused) { focused = outputNames[i]; break }
            root.selectedMonitor = outputNames.indexOf(focused) >= 0 ? focused : (outputNames.length ? outputNames[0] : "")
          }
          root.gotInitialState = true
          root.loadDraft()
        } else if (JSON.stringify(incoming) !== JSON.stringify(root.baselineConfig)) {
          var expected = Util.cloneJson(root.baselineConfig)
          if (root.savePending) expected.monitors[root.saveMonitor] = root.saveRecord
          if (!root.savePending || JSON.stringify(incoming) !== JSON.stringify(expected)) root.settingsConflict = true
        }
      } catch (e) { root.errorText = String(e) }
    } }
    onExited: function(exitCode) { if (exitCode !== 0) root.errorText = "Could not read wallpaper settings." }
  }
  Process {
    id: listProcess
    stdout: StdioCollector { onStreamFinished: {
      try {
        var paths = JSON.parse(text)
        if (root.listingFolder === root.folder) root.imageFiles = paths
        else root.listQueued = true
      } catch (e) {
        if (root.listingFolder === root.folder) {
          root.imageFiles = []
          root.errorText = "Could not read images from this folder."
        } else root.listQueued = true
      }
    } }
    onExited: if (root.listQueued) root.refreshImages()
  }
  Process {
    id: prepareProcess
    stdout: StdioCollector { onStreamFinished: {
      try {
        var result = JSON.parse(text)
        if (root.preparingPath !== root.imagePath || root.preparingRotation !== root.rotation) { root.prepareQueued = true; return }
        root.prepared = result
        root.preparedSource = root.imagePath
        root.preparedRotation = root.preparingRotation
        var copy = Object.assign({}, root.unreadable); delete copy[root.imagePath]; root.unreadable = copy
        root.errorText = ""
      } catch (e) {
        if (root.preparingPath === root.imagePath && root.preparingRotation === root.rotation) {
          root.errorText = "Could not open this image. Choose another image."
          var copy = Object.assign({}, root.unreadable); copy[root.imagePath] = true; root.unreadable = copy
        } else root.prepareQueued = true
      }
    } }
    stderr: StdioCollector { onStreamFinished: if (text.indexOf("ImageMagick is unavailable") >= 0) { root.errorText = "ImageMagick is unavailable. Install it to prepare wallpaper images."; var copy = Object.assign({}, root.unreadable); delete copy[root.preparingPath]; root.unreadable = copy } }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.preparingPath === root.imagePath && root.preparingRotation === root.rotation
          && root.errorText.indexOf("ImageMagick is unavailable") < 0)
        root.errorText = "Could not open this image. Choose another image."
      if (root.prepareQueued) root.prepareSelection()
    }
  }
  Process { id: previewProcess }
  Process { id: cancelProcess; command: ["omarchy-shell", "-q", "background", "cancelPreview"] }
  Process {
    id: saveProcess
    onExited: function(exitCode) {
      if (exitCode === 0) statusProcess.running = true
      else { root.savePending = false; root.errorText = "Could not save wallpaper settings. Try again." }
    }
  }
  Process {
    id: statusProcess
    command: ["omarchy-shell", "background", "editorState"]
    stdout: StdioCollector { onStreamFinished: {
      try {
        var state = JSON.parse(text)
        var updatedConfig = Model.normalizeConfig(state.config)
        root.connected = state.monitors || ({})
        root.serviceErrors = state.errors || ({})
        root.sharedImage = String(state.sharedBackground || "")
        root.serviceRevision = Number(state.revision || 0)
        if (root.serviceRevision > root.saveRevision) {
          if (updatedConfig.monitors[root.saveMonitor] && JSON.stringify(updatedConfig.monitors[root.saveMonitor]) === JSON.stringify(root.saveRecord)) {
            root.config = updatedConfig
            root.baselineConfig = Util.cloneJson(updatedConfig)
            root.errorText = "Saved settings."
            root.savePending = false
          } else if ((state.errors && state.errors.save) || !state.monitors || !state.monitors[root.saveMonitor]) {
            root.errorText = "Could not save wallpaper settings. Try again."
            root.savePending = false
          } else savePoll.restart()
        } else savePoll.restart()
      } catch (e) { root.errorText = "Could not confirm saved settings."; root.savePending = false }
    } }
  }
  Timer { id: savePoll; interval: 300; repeat: false; onTriggered: statusProcess.running = true }
  Timer { interval: 1200; repeat: true; running: root.opened; onTriggered: if (!stateProcess.running && !statusProcess.running) stateProcess.running = true }
  Timer { id: previewTimer; interval: 1000; repeat: true; onTriggered: { if (root.previewSeconds > 0) root.previewSeconds--; if (!root.previewSeconds) previewTimer.stop() } }
  Process {
    id: imagePicker
    command: ["zenity", "--file-selection", "--title=Choose wallpaper"]
    stdout: StdioCollector { onStreamFinished: { var path = root.pickerResult(text); if (path) root.selectImage(path) } }
    onExited: if (root.pickerHidden) { root.pickerHidden = false; root.opened = true }
  }
  Process {
    id: folderPicker
    command: ["zenity", "--file-selection", "--directory", "--title=Choose wallpaper folder"]
    stdout: StdioCollector { onStreamFinished: { var path = root.pickerResult(text); if (path) root.chooseFolder(path) } }
    onExited: if (root.pickerHidden) { root.pickerHidden = false; root.opened = true }
  }

  PanelWindow {
    id: panel
    visible: root.opened && !root.pickerHidden
    anchors { top: true; bottom: true; left: true; right: true }
    color: root.previewSeconds > 0 ? "transparent" : Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.88)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-wallpaper-editor"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    Rectangle {
      id: card
      anchors.horizontalCenter: parent.horizontalCenter
      y: root.previewSeconds > 0 ? 16 : (parent.height - height) / 2
      width: Math.min(parent.width - 32, root.previewSeconds > 0 ? 360 : 1180)
      height: root.previewSeconds > 0 ? 72 : Math.min(parent.height - 32, 780)
      color: Commons.Color.background; radius: Style.cornerRadius; border.color: Commons.Color.popups.border
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onEscapePressed: root.close()
      onVisibleChanged: if (visible) Qt.callLater(function() { card.forceActiveFocus() })
      RowLayout {
        anchors.fill: parent
        anchors.margins: 16
        visible: root.previewSeconds > 0
        Text { text: "Preview active · " + root.previewSeconds + " seconds"; color: Commons.Color.foreground; Layout.fillWidth: true }
        Button { text: "End preview"; focusable: true; onClicked: root.endPreview() }
      }
      Flickable {
        visible: root.previewSeconds === 0
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight + 40
        clip: true
        ColumnLayout {
          id: content
          x: 20
          y: 20
          width: parent.width - 40
          spacing: 12
        RowLayout {
          Text { text: "Wallpaper per monitor"; color: Commons.Color.foreground; font.pixelSize: Style.font.title; font.bold: true; Layout.fillWidth: true }
          Dropdown { label: "Monitor"; options: root.screens.map(function(s) { var name = String(s.name || ""), output = root.connected[name] || {}; return { value: name, label: name + " · " + (output.width || s.width) + "×" + (output.height || s.height) + " · transform " + (output.transform || 0) + " · " + (output.scale || 1) + "×" } }); value: root.selectedMonitor; onChanged: function(v) { root.selectMonitor(v) } }
          Button { text: "Close"; focusable: true; onClicked: root.close() }
        }
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 78
          Repeater {
            model: Object.keys(root.connected)
            delegate: Rectangle {
              required property string modelData
              readonly property var bounds: root.overviewRect(modelData)
              x: bounds.x
              y: bounds.y
              width: bounds.width
              height: bounds.height
              radius: Style.cornerRadius
              color: modelData === root.selectedMonitor ? Style.selectedFillFor(Commons.Color.foreground, Commons.Color.accent) : Commons.Color.popups.background
              border.color: modelData === root.selectedMonitor ? Commons.Color.accent : Commons.Color.popups.border
              Text { anchors.centerIn: parent; text: parent.modelData; color: Commons.Color.foreground; font.pixelSize: Style.font.caption }
              MouseArea {
                anchors.fill: parent
                onClicked: root.selectMonitor(parent.modelData)
              }
            }
          }
        }
        Text { text: root.settingsConflict ? "Saved settings changed. Reopen the editor to reload." : (root.serviceErrors[root.selectedMonitor] || root.errorText || ""); visible: text.length > 0; color: Commons.Color.urgent; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        GridLayout {
          columns: card.width < 960 ? 1 : 3
          Layout.fillWidth: true
          Layout.preferredHeight: Math.max(card.width < 960 ? 780 : 320, card.height - 260)
          columnSpacing: 16
          rowSpacing: 16
          ColumnLayout {
            Layout.preferredWidth: 280; Layout.fillHeight: true
            RowLayout {
              Button {
                focusable: true
                text: "Choose image"
                onClicked: { root.opened = false; root.pickerHidden = true; Qt.callLater(function() { imagePicker.running = true }) }
              }
              Button {
                focusable: true
                text: "Choose folder"
                onClicked: { root.opened = false; root.pickerHidden = true; Qt.callLater(function() { folderPicker.running = true }) }
              }
            }
            RowLayout {
              Button {
                focusable: true
                text: "Previous"
                enabled: root.readableImageCount > 1
                onClicked: root.navigate(-1)
              }
              Button {
                focusable: true
                text: "Next"
                enabled: root.readableImageCount > 1
                onClicked: root.navigate(1)
              }
            }
            Text { visible: root.imageFiles.length === 0; text: "No images in this folder. Choose another folder."; color: Commons.Color.foreground; Layout.fillWidth: true; Layout.minimumWidth: 0; wrapMode: Text.WordWrap }
            GridView { Layout.fillWidth: true; Layout.fillHeight: true; clip: true; cellWidth: 128; cellHeight: 100; model: root.imageFiles
              delegate: Item { required property string modelData; width: 124; height: 96
                Image {
                  anchors.fill: parent; source: Util.fileUrl(modelData); sourceSize: Qt.size(160, 120); fillMode: Image.PreserveAspectCrop; asynchronous: true
                  onStatusChanged: if (status === Image.Error && !root.unreadable[modelData]) {
                    var copy = Object.assign({}, root.unreadable); copy[modelData] = true; root.unreadable = copy
                  }
                }
                Text { anchors.centerIn: parent; visible: !!root.unreadable[modelData]; text: "Can't open image"; color: Commons.Color.urgent; wrapMode: Text.WordWrap; width: parent.width; horizontalAlignment: Text.AlignHCenter }
                Rectangle { anchors.fill: parent; color: "transparent"; border.width: root.imagePath === modelData ? 3 : 0; border.color: Commons.Color.accent }
                MouseArea { anchors.fill: parent; onClicked: root.selectImage(modelData) }
              }
            }
          }
          ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            Text { text: root.selectedMonitor + " · " + root.canvas().width + " × " + root.canvas().height + " px · transform " + (root.canvas().transform || 0) + " · scale " + (root.canvas().scale || 1) + "× · image rotation " + root.rotation + "°"; color: Commons.Color.foreground }
            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true
              WallpaperFrame {
                anchors.centerIn: parent
                width: root.canvas().width > 0 && root.canvas().height > 0
                  ? Math.min(parent.width, parent.height * root.canvas().width / root.canvas().height) : parent.width
                height: root.canvas().width > 0 && root.canvas().height > 0
                  ? width * root.canvas().height / root.canvas().width : parent.height
                leaseOwner: "editor"
                source: (root.imagePath || root.rotation !== 0) ? "" : root.sharedImage
                originalSource: root.imagePath || (root.rotation !== 0 ? root.sharedImage : "")
                allowRawFallback: !root.imagePath
                rotation: root.rotation
                canvasWidth: root.canvas().width
                canvasHeight: root.canvas().height
                record: root.record()
                onFailed: root.errorText = "Could not open this image. Choose another image."
              }
            }
            Text { text: root.selectionReady ? "Image: " + root.prepared.width + " × " + root.prepared.height : root.imagePath ? (prepareProcess.running ? "Preparing image…" : "Image is not prepared") : "Theme wallpaper"; color: Commons.Color.foreground }
          }
          ColumnLayout {
            Layout.preferredWidth: 230
            Dropdown { label: "Sizing"; options: [{value:"fill",label:"Fill"},{value:"fit",label:"Fit"},{value:"stretch",label:"Stretch"},{value:"original",label:"Original size"},{value:"custom",label:"Custom size"}]; value: root.mode; onChanged: function(v) { root.mode = String(v) } }
            Text { visible: (root.mode === "original" || root.mode === "custom") && root.canvas().physical !== true; text: "Physical monitor dimensions are unavailable; Original size and Custom size cannot be applied."; color: Commons.Color.urgent; Layout.fillWidth: true; Layout.minimumWidth: 0; wrapMode: Text.WordWrap }
            RowLayout {
              visible: root.mode === "custom"
              NumberField { label: "Width (px)"; from: 1; to: 32768; value: root.widthPx; enabled: root.canvas().physical === true; onModified: function(v) { root.widthPx = Number(v) } }
              NumberField { label: "Height (px)"; from: 1; to: 32768; value: root.heightPx; enabled: root.canvas().physical === true; onModified: function(v) { root.heightPx = Number(v) } }
            }
            Text { text: root.recommendation ? "Recommended: " + (root.recommendation.mode === "fill" ? "Fill · " + Math.round(root.recommendation.croppedPercent) + "% cropped" : "Fit · " + Math.round(100 * (1 - root.recommendation.retainedFraction)) + "% borders") : ""; color: Commons.Color.foreground; Layout.fillWidth: true; Layout.minimumWidth: 0; wrapMode: Text.WordWrap }
            Text { visible: !!root.recommendation && root.recommendation.enlarged; text: "This image may look blurry when enlarged"; color: Commons.Color.urgent; Layout.fillWidth: true; Layout.minimumWidth: 0; wrapMode: Text.WordWrap }
            Button { text: "Use recommendation"; focusable: true; enabled: !!root.recommendation; onClicked: if (root.recommendation) root.mode = root.recommendation.mode }
            Text { visible: root.distorted; text: "This sizing changes the image proportions."; color: Commons.Color.urgent; Layout.fillWidth: true; Layout.minimumWidth: 0; wrapMode: Text.WordWrap }
            RowLayout {
              Button { text: "Rotate left"; focusable: true; onClicked: { root.rotation = (root.rotation + 270) % 360; if (root.imagePath) root.selectImage(root.imagePath) } }
              Button { text: "Rotate right"; focusable: true; onClicked: { root.rotation = (root.rotation + 90) % 360; if (root.imagePath) root.selectImage(root.imagePath) } }
            }
            Repeater {
              model: [0, 1, 2]
              delegate: RowLayout {
                required property int index
                Repeater {
                  model: [0, 1, 2]
                  delegate: Button {
                    focusable: true
                    required property int index
                    readonly property int positionIndex: parent.index * 3 + index
                    text: ["↖", "↑", "↗", "←", "●", "→", "↙", "↓", "↘"][positionIndex]
                    Accessible.name: ["Top left", "Top center", "Top right", "Middle left", "Center", "Middle right", "Bottom left", "Bottom center", "Bottom right"][positionIndex]
                    onClicked: { root.anchorX = index / 2; root.anchorY = parent.index / 2 }
                  }
                }
              }
            }
            Button { text: "Use theme wallpaper"; focusable: true; onClicked: { root.imagePath = ""; root.prepared = {path:"",width:0,height:0}; root.preparedSource = ""; root.preparedRotation = -1 } }
          }
        }
        RowLayout {
          Layout.fillWidth: true
          Button { text: "Preview on desktop"; focusable: true; enabled: !root.savePending && (!root.imagePath || root.selectionReady) && (["original", "custom"].indexOf(root.mode) < 0 || root.canvas().physical === true); onClicked: root.preview() }
          Item { Layout.fillWidth: true }
          Button { text: "Cancel"; focusable: true; onClicked: root.close() }
          Button { text: root.savePending ? "Saving…" : "Apply"; focusable: true; enabled: !root.savePending && !root.settingsConflict && root.canvas().width > 0 && (!root.imagePath || root.selectionReady) && (["original", "custom"].indexOf(root.mode) < 0 || root.canvas().physical === true); onClicked: root.apply() }
        }
      }
      }
    }
  }
}
