import Quickshell.Io
import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: root
  property string source: ""
  property string originalSource: ""
  property int rotation: 0
  property string preparedSource: ""
  property int preparedRotation: -1
  property int intrinsicWidth: 0
  property int intrinsicHeight: 0
  property int canvasWidth: 0
  property int canvasHeight: 0
  property var record: ({ mode: "fill", anchorX: 0.5, anchorY: 0.5 })
  property bool asynchronous: true
  property bool allowRawFallback: false
  property bool rawFallback: false
  property string preparedPath: ""
  property string prepareError: ""
  property string preparingSource: ""
  property int preparingRotation: 0
  property bool prepareQueued: false
  property string leaseOwner: ""
  property var leasePending: null
  signal ready()
  readonly property bool imageReady: frameImage.status === Image.Ready
    && (!originalSource || rawFallback || (preparedSource === originalSource && preparedRotation === rotation))
  signal failed(string message)
  clip: true
  Rectangle { anchors.fill: parent; color: "black" }
  readonly property var geometry: Model.layout(intrinsicWidth, intrinsicHeight, canvasWidth, canvasHeight, record)
  function updateLease(paths) {
    if (!leaseOwner) return
    leasePending = paths
    runLease()
  }
  function runLease() {
    if (!leaseOwner || leaseProcess.running || leasePending === null) return
    var paths = leasePending
    leasePending = null
    leaseProcess.command = ["/usr/bin/python3",
      decodeURIComponent(Qt.resolvedUrl("scripts/editor-io.py").toString()).replace(/^file:\/\//, ""),
      "lease", leaseOwner, JSON.stringify(paths)]
    leaseProcess.running = true
  }
  function prepare() {
    if (!originalSource) { preparedPath = ""; prepareError = ""; rawFallback = false; updateLease(source ? [source] : []); return }
    if (prepareProcess.running) { prepareQueued = true; return }
    prepareQueued = false
    preparingSource = originalSource
    preparingRotation = rotation
    rawFallback = false
    prepareError = ""
    prepareProcess.command = ["/usr/bin/python3",
      decodeURIComponent(Qt.resolvedUrl("scripts/editor-io.py").toString()).replace(/^file:\/\//, ""),
      "prepare", preparingSource, String(preparingRotation), leaseOwner, preparedPath]
    prepareProcess.running = true
  }
  Process {
    id: prepareProcess
    stdout: StdioCollector { onStreamFinished: {
      try {
        var result = JSON.parse(text)
        if (root.preparingSource !== root.originalSource || root.preparingRotation !== root.rotation) {
          root.prepareQueued = true
          return
        }
        root.preparedPath = result.path
        root.intrinsicWidth = result.width
        root.intrinsicHeight = result.height
        root.preparedSource = root.preparingSource
        root.preparedRotation = root.preparingRotation
        root.rawFallback = false
        root.prepareError = ""
      } catch (e) {
        if (root.preparingSource !== root.originalSource || root.preparingRotation !== root.rotation) root.prepareQueued = true
        else { root.prepareError = String(e); root.rawFallback = root.allowRawFallback; root.failed(root.prepareError) }
      }
    } }
    stderr: StdioCollector { onStreamFinished: if (text.indexOf("ImageMagick is unavailable") >= 0) root.prepareError = "ImageMagick is unavailable; install it to prepare wallpaper images." }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.preparingSource === root.originalSource && root.preparingRotation === root.rotation) {
        if (root.prepareError.indexOf("ImageMagick is unavailable") < 0) root.prepareError = "Could not prepare wallpaper image"
        root.rawFallback = root.allowRawFallback
        root.failed(root.prepareError)
      } else if (exitCode !== 0) root.prepareQueued = true
      if (root.prepareQueued) root.prepare()
    }
  }
  Process {
    id: leaseProcess
    onExited: root.runLease()
  }
  onOriginalSourceChanged: prepare()
  onSourceChanged: if (!originalSource) updateLease(source ? [source] : [])
  onRotationChanged: prepare()
  Component.onDestruction: updateLease([])
  Image {
    id: frameImage
    source: Util.fileUrl(root.originalSource ? (root.rawFallback ? root.originalSource : root.preparedPath) : root.source)
    asynchronous: root.asynchronous
    cache: true
    smooth: true
    fillMode: Image.Stretch
    x: root.geometry ? root.geometry.x * root.width / root.canvasWidth : 0
    y: root.geometry ? root.geometry.y * root.height / root.canvasHeight : 0
    width: root.geometry ? root.geometry.width * root.width / root.canvasWidth : 0
    height: root.geometry ? root.geometry.height * root.height / root.canvasHeight : 0
    onStatusChanged: {
      if (status === Image.Ready) {
        if (!root.originalSource || root.rawFallback) {
          root.intrinsicWidth = implicitWidth
          root.intrinsicHeight = implicitHeight
        } else root.updateLease([root.preparedPath])
        root.ready()
      } else if (status === Image.Error) root.failed("Could not load wallpaper image")
    }
  }
}
