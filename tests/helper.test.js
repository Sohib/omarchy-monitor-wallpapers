const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const crypto = require("node:crypto")
const { spawnSync } = require("node:child_process")

const helper = path.resolve(__dirname, "../scripts/editor-io.py")
const hasMagick = spawnSync("magick", ["-version"], { stdio: "ignore" }).status === 0

test("guarded config I/O and source-safe image preparation", { skip: !hasMagick }, () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "wallpaper-editor-test-"))
  const configDir = path.join(home, ".config/omarchy")
  fs.mkdirSync(configDir, { recursive: true })
  const run = (...args) => spawnSync("python3", [helper, ...args], { encoding: "utf8", env: { ...process.env, HOME: home } })

  try {
    const withoutLegacy = JSON.parse(run("read").stdout)
    assert.equal(withoutLegacy.missing, true)
    assert.match(withoutLegacy.migrationNotice, /former DP-3 wallpaper is unavailable/)


    const imagesDir = path.join(home, "images")
    fs.mkdirSync(imagesDir)
    const source = path.join(imagesDir, "a 'quoted'\nimage.png")
    assert.equal(spawnSync("magick", ["-size", "80x120", "xc:red", source]).status, 0)
    const legacy = path.join(home, ".config/omarchy/backgrounds/tokyo-night/winding-road-portrait-2160x3840.jpg")
    fs.mkdirSync(path.dirname(legacy), { recursive: true })
    fs.copyFileSync(source, legacy)
    const migration = JSON.parse(run("read").stdout)
    assert.equal(migration.monitors["DP-3"].image, legacy)
    assert.equal(migration.monitors["DP-3"].rotation, 0)
    assert.equal(migration.monitors["DP-3"].mode, "fill")
    fs.rmSync(path.dirname(path.dirname(legacy)), { recursive: true, force: true })
    const saved = { version: 1, monitors: { "DP-3": { image: null, mode: "fill", rotation: 0, anchorX: 0.5, anchorY: 0.5, widthPx: 2160, heightPx: 3840 } } }
    assert.equal(run("write", JSON.stringify(saved)).status, 0)
    assert.deepEqual(JSON.parse(run("read").stdout), saved)
    assert.notEqual(run("write", JSON.stringify({ version: 9, monitors: {} })).status, 0)

    const before = crypto.createHash("sha256").update(fs.readFileSync(source)).digest("hex")
    const prepared = run("prepare", source, "90")
    assert.equal(prepared.status, 0, prepared.stderr)
    assert.deepEqual(JSON.parse(prepared.stdout).width, 120)
    assert.equal(JSON.parse(prepared.stdout).height, 80)
    assert.equal(crypto.createHash("sha256").update(fs.readFileSync(source)).digest("hex"), before)
    const asymmetric = path.join(imagesDir, "clockwise.png")
    assert.equal(spawnSync("magick", ["-size", "2x3", "xc:black", "-fill", "red", "-draw", "point 0,0", "-fill", "blue", "-draw", "point 1,0", "-fill", "green", "-draw", "point 0,2", "-fill", "yellow", "-draw", "point 1,2", asymmetric]).status, 0)
    const rotated = JSON.parse(run("prepare", asymmetric, "90").stdout)
    const corners = spawnSync("magick", [rotated.path, "-format", "%[pixel:p{2,0}] %[pixel:p{2,1}] %[pixel:p{0,0}] %[pixel:p{0,1}]", "info:"], { encoding: "utf8" })
    assert.equal(corners.stdout, "srgb(255,0,0) srgb(0,0,255) srgb(0,128,0) srgb(255,255,0)")
    const cacheDir = path.join(home, ".cache/omarchy/wallpaper-editor")
    fs.mkdirSync(cacheDir, { recursive: true })
    const protectedImage = path.join(cacheDir, "currently-displayed.png")
    for (let i = 0; i < 35; i++) {
      const file = path.join(cacheDir, `old-${String(i).padStart(2, "0")}.png`)
      fs.writeFileSync(file, "cache fixture")
      fs.utimesSync(file, new Date(1000 + i), new Date(1000 + i))
    }
    fs.renameSync(path.join(cacheDir, "old-00.png"), protectedImage)
    assert.equal(run("lease", "other-frame", JSON.stringify([protectedImage])).status, 0)
    const leasedPrepare = run("prepare", source, "90", "test-frame", protectedImage)
    assert.equal(leasedPrepare.status, 0, leasedPrepare.stderr)
    assert.ok(fs.existsSync(protectedImage), "cache pruning keeps a file held by a live renderer lease")
    assert.ok(fs.readdirSync(cacheDir).filter((name) => name.endsWith(".png")).length <= 32)
    
    const listed = run("images", imagesDir)
    assert.equal(listed.status, 0)
    assert.deepEqual(JSON.parse(listed.stdout), [source, asymmetric])

    fs.unlinkSync(path.join(configDir, "background-editor.json"))
    fs.symlinkSync(source, path.join(configDir, "background-editor.json"))
    assert.notEqual(run("read").status, 0)
  } finally {
    fs.rmSync(home, { recursive: true, force: true })
  }
})

test("EXIF orientation precedes requested clockwise rotation without altering the source", {
  skip: !hasMagick || spawnSync("exiv2", ["-V"], { stdio: "ignore" }).status !== 0,
}, () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "wallpaper-exif-test-"))
  const source = path.join(home, "oriented.jpg")
  try {
    assert.equal(spawnSync("magick", ["-size", "80x120", "xc:red", source]).status, 0)
    assert.equal(spawnSync("exiv2", ["-M", "set Exif.Image.Orientation Short 6", source]).status, 0)
    const before = crypto.createHash("sha256").update(fs.readFileSync(source)).digest("hex")
    const run = (rotation) => spawnSync("python3", [helper, "prepare", source, String(rotation)], {
      encoding: "utf8", env: { ...process.env, HOME: home },
    })
    const oriented = run(0)
    assert.equal(oriented.status, 0, oriented.stderr)
    const upright = JSON.parse(oriented.stdout)
    assert.deepEqual([upright.width, upright.height], [120, 80])
    const rotated = run(90)
    assert.equal(rotated.status, 0, rotated.stderr)
    const clockwise = JSON.parse(rotated.stdout)
    assert.deepEqual([clockwise.width, clockwise.height], [80, 120])
    assert.equal(crypto.createHash("sha256").update(fs.readFileSync(source)).digest("hex"), before)
  } finally {
    fs.rmSync(home, { recursive: true, force: true })
  }
})
