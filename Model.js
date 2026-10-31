function finitePositive(value) {
  return typeof value === "number" && Number.isFinite(value) && value > 0
}

function normalizeRecord(value, canvas) {
  var src = value && typeof value === "object" && !Array.isArray(value) ? value : {}
  var cw = canvas && Number.isInteger(canvas.width) && canvas.width > 0 ? canvas.width : 1
  var ch = canvas && Number.isInteger(canvas.height) && canvas.height > 0 ? canvas.height : 1
  var mode = ["fill", "fit", "stretch", "original", "custom"].indexOf(src.mode) >= 0 ? src.mode : "fill"
  var rotation = [0, 90, 180, 270].indexOf(src.rotation) >= 0 ? src.rotation : 0
  var image = src.image === null || typeof src.image === "string" && src.image.length > 0 ? src.image : null
  function anchor(n) { return typeof n === "number" && Number.isFinite(n) && n >= 0 && n <= 1 ? n : 0.5 }
  function dimension(n, fallback) { return Number.isInteger(n) && n > 0 && n <= 32768 ? n : fallback }
  return { image: image, mode: mode, rotation: rotation, anchorX: anchor(src.anchorX), anchorY: anchor(src.anchorY),
    widthPx: dimension(src.widthPx, cw), heightPx: dimension(src.heightPx, ch) }
}

function validateRecord(value, canvas) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid wallpaper record")
  if (["fill", "fit", "stretch", "original", "custom"].indexOf(value.mode) < 0) throw new Error("Unsupported sizing mode")
  if ([0, 90, 180, 270].indexOf(value.rotation) < 0) throw new Error("Unsupported image rotation")
  if (![value.anchorX, value.anchorY].every(function(n) { return typeof n === "number" && Number.isFinite(n) && n >= 0 && n <= 1 }))
    throw new Error("Position anchors must be between zero and one")
  if (value.image !== null && (typeof value.image !== "string" || value.image.charAt(0) !== "/"))
    throw new Error("Wallpaper path must be absolute or null")
  if (value.mode === "custom" && (![value.widthPx, value.heightPx].every(function(n) {
    return Number.isInteger(n) && n > 0 && n <= 32768
  }))) throw new Error("Custom size must use positive integer pixels up to 32768")
  return normalizeRecord(value, canvas)
}

function normalizeConfig(value) {
  if (!value || typeof value !== "object" || Array.isArray(value) || value.version !== 1)
    throw new Error("Unsupported wallpaper editor settings version")
  var records = value.monitors
  if (!records || typeof records !== "object" || Array.isArray(records)) throw new Error("Invalid monitor settings")
  var monitors = {}
  Object.keys(records).forEach(function(name) {
    if (name && name.length <= 128) monitors[name] = normalizeRecord(records[name], null)
  })
  return { version: 1, monitors: monitors }
}

function layout(imageWidth, imageHeight, canvasWidth, canvasHeight, record) {
  if (![imageWidth, imageHeight, canvasWidth, canvasHeight].every(finitePositive)) return null
  var r = normalizeRecord(record, { width: canvasWidth, height: canvasHeight })
  var w, h
  if (r.mode === "stretch") { w = canvasWidth; h = canvasHeight }
  else if (r.mode === "original") { w = imageWidth; h = imageHeight }
  else if (r.mode === "custom") { w = r.widthPx; h = r.heightPx }
  else {
    var scale = r.mode === "fill" ? Math.max(canvasWidth / imageWidth, canvasHeight / imageHeight)
      : Math.min(canvasWidth / imageWidth, canvasHeight / imageHeight)
    w = imageWidth * scale; h = imageHeight * scale
  }
  return { x: (canvasWidth - w) * r.anchorX, y: (canvasHeight - h) * r.anchorY, width: w, height: h,
    scaleX: w / imageWidth, scaleY: h / imageHeight }
}

function recommend(imageWidth, imageHeight, canvasWidth, canvasHeight, rotation) {
  if (![imageWidth, imageHeight, canvasWidth, canvasHeight].every(finitePositive)) return null
  if ([90, 270].indexOf(rotation) >= 0) { var t = imageWidth; imageWidth = imageHeight; imageHeight = t }
  var ratio = imageWidth / imageHeight, canvasRatio = canvasWidth / canvasHeight
  var retained = Math.min(ratio / canvasRatio, canvasRatio / ratio)
  var mode = retained >= 0.85 ? "fill" : "fit"
  var scale = mode === "fill" ? Math.max(canvasWidth / imageWidth, canvasHeight / imageHeight)
    : Math.min(canvasWidth / imageWidth, canvasHeight / imageHeight)
  return { mode: mode, retainedFraction: retained, croppedPercent: 100 * (1 - retained), scale: scale,
    enlarged: scale > 1 }
}

if (typeof module !== "undefined") module.exports = { normalizeConfig: normalizeConfig, normalizeRecord: normalizeRecord, validateRecord: validateRecord, layout: layout, recommend: recommend }
