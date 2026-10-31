const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

test("matching aspect ratio fills without crop", () => {
  assert.equal(Model.recommend(4000, 2000, 2000, 1000, 0).mode, "fill")
  assert.equal(Model.recommend(4000, 2000, 2000, 1000, 0).croppedPercent, 0)
})

test("portrait canvas recommends fit for a landscape image", () => {
  const result = Model.recommend(4000, 2000, 1000, 2000, 0)
  assert.equal(result.mode, "fit")
  assert.equal(Math.round(result.croppedPercent), 75)
})

test("original size respects centered anchor and fractional stage mapping", () => {
  const box = Model.layout(1000, 500, 2000, 1000, { mode: "original", anchorX: 0.5, anchorY: 0.5 })
  assert.deepEqual([box.x, box.y, box.width, box.height], [500, 250, 1000, 500])
  assert.equal(box.width * (777.25 / 2000), 388.625)
})

test("rotation swaps dimensions before recommendation", () => {
  assert.equal(Model.recommend(4000, 2000, 1000, 2000, 90).mode, "fill")
})

test("custom dimensions and invalid dimensions", () => {
  assert.deepEqual(Model.layout(100, 80, 1000, 800, { mode: "custom", widthPx: 321, heightPx: 654 }).width, 321)
  assert.equal(Model.layout(NaN, 80, 1000, 800, {}), null)
})

test("schema versions are strict and invalid optional record fields normalize", () => {
  assert.throws(() => Model.normalizeConfig({ version: 2, monitors: {} }), /Unsupported/)
  assert.deepEqual(Model.normalizeRecord({ mode: "wrong", rotation: 45, anchorX: 3 }, { width: 1920, height: 1080 }), {
    image: null, mode: "fill", rotation: 0, anchorX: 0.5, anchorY: 0.5, widthPx: 1920, heightPx: 1080
  })
})

test("Apply rejects invalid custom dimensions and non-absolute image paths", () => {
  const base = { image: null, mode: "custom", rotation: 0, anchorX: 0.5, anchorY: 0.5, widthPx: 1200, heightPx: 800 }
  assert.equal(Model.validateRecord(base, { width: 1920, height: 1080 }).widthPx, 1200)
  assert.throws(() => Model.validateRecord({ ...base, widthPx: 0 }, { width: 1920, height: 1080 }), /Custom size/)
  assert.throws(() => Model.validateRecord({ ...base, image: "relative.jpg" }, { width: 1920, height: 1080 }), /absolute/)
})
