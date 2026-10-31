# Omarchy Wallpaper Editor

A native per-monitor wallpaper editor for Omarchy's Quickshell desktop. Choose independent images, adjust their sizing and position, rotate them, and preview changes before saving—without installing a separate wallpaper renderer.

Built as a user-owned clone of `omarchy.background`. Plugin ID: **`suhayb.background`**.

## Features

- Independent wallpaper and draft settings for each monitor, identified by connector name.
- **Fill**, **Fit**, **Stretch**, **Original size**, and **Custom size** in physical pixels.
- Image-only clockwise rotation in 90° steps; monitor configuration is never changed.
- Nine-position alignment for crops and black borders.
- Fill/Fit recommendations based on aspect ratio, with crop/border percentages and enlargement warnings.
- Folder thumbnails and manual Previous/Next navigation; no slideshow.
- In-editor preview plus a temporary **20-second desktop preview** with an unobtrusive countdown bar.
- Atomic settings persistence, external-change conflict detection, and last-good image fallback.
- Native shared-wallpaper and theme-transition integration.

## Requirements

- Omarchy with its native Quickshell shell and plugin manager.
- Hyprland and `hyprctl`.
- Python 3, ImageMagick (`magick` and `identify`), and Zenity.
- Git for installation; Node.js only for running the tests.

The plugin uses Omarchy's `qs.Commons` and `qs.Ui` components. It is **not a standalone Quickshell configuration** and is not intended for arbitrary Hyprland distributions.

Check dependencies before installation:

```bash
command -v omarchy omarchy-shell hyprctl python3 magick identify zenity git
```

No dependency installation is performed automatically. Image preparation needs ImageMagick; the editor reports a missing dependency rather than installing packages.

## Install

### Using Omarchy's plugin manager

```bash
omarchy plugin add https://github.com/Sohib/omarchy-wallpaper-editor.git
omarchy plugin enable suhayb.background
```

For a private GitHub repository, authenticate Git first and use an SSH URL:

```bash
omarchy plugin add git@github.com:Sohib/omarchy-wallpaper-editor.git
omarchy plugin enable suhayb.background
```

Enabling this clone replaces the built-in `omarchy.background` through Omarchy's clone mechanism. **Do not enable another wallpaper renderer alongside it.** Review other wallpaper services before installing.

If a plugin with the same ID is already installed, do not overwrite its directory. Back up its source and settings and use the development workflow below, or update the existing installation.

### Development checkout

Keep the source checkout separate from the installed copy. Omarchy's validator rejects symlinked plugin folders.

```bash
mkdir -p ~/Documents/projects ~/.config/omarchy/plugins
git clone git@github.com:Sohib/omarchy-wallpaper-editor.git ~/Documents/projects/omarchy-wallpaper-editor
cd ~/Documents/projects/omarchy-wallpaper-editor
mkdir -p ~/.config/omarchy/plugins/suhayb.background
tar --exclude=.git -cf - . | tar -xf - -C ~/.config/omarchy/plugins/suhayb.background
omarchy plugin validate ~/.config/omarchy/plugins/suhayb.background
omarchy-shell shell rescanPlugins
omarchy plugin enable suhayb.background
```

Use an empty installation directory for the first copy. Back up any existing installation before replacing it. The project checkout is the source of truth; edits there are not automatically installed.

After source changes, repeat the copy and validation steps, then restart the shell:

```bash
omarchy restart shell
```

## Open and use

```bash
omarchy-shell shell summon suhayb.background
```

You can also double-left-click an unobstructed desktop background. Double-right-click retains the native theme selector.

1. Choose the target monitor from the dropdown or monitor overview.
2. Browse Omarchy's current theme wallpapers (`~/.local/state/omarchy/current/theme/backgrounds`) by default, even when the saved image is elsewhere. Choose an image or folder explicitly to browse another location; that folder is remembered per monitor for the session.
3. Pick a sizing mode, rotation, and position. Custom width and height are independent physical-pixel values, each from 1 to 32768.
4. Use **Use recommendation** if desired; recommendations never silently change your selected mode.
5. Select **Preview on desktop** to inspect the wallpaper without saving. The editor collapses to a countdown bar; **End preview** returns to the editor, and timeout restores the committed wallpaper automatically.
6. Select **Apply** to save only the selected monitor. The editor stays open after a confirmed save.

**Cancel**, Escape, or closing the editor discards unsaved drafts and cancels temporary preview. Choosing a file temporarily hides the overlay without discarding your draft; cancelling the chooser preserves it.

**Use theme wallpaper** clears the independent image for the selected monitor so it follows Omarchy's shared wallpaper. Existing per-monitor sizing and rotation controls remain available.

Original size and Custom size require verified physical monitor metadata. When that metadata is unavailable, the editor disables those modes for Apply; Fit, Fill, and Stretch can still use screen aspect ratio.

## Settings and cache

Settings are stored only in:

```text
~/.config/omarchy/background-editor.json
```

Example:

```json
{
  "version": 1,
  "monitors": {
    "DP-3": {
      "image": "/home/you/Pictures/portrait.jpg",
      "mode": "fit",
      "rotation": 0,
      "anchorX": 0.5,
      "anchorY": 0.5,
      "widthPx": 2160,
      "heightPx": 3840
    }
  }
}
```

`image: null` follows the shared wallpaper. Connector names are exact identities: disconnected records are retained, but renamed connectors are not automatically matched. Rotation is image-only and clockwise; supported values are 0, 90, 180, and 270.

Prepared images live under `~/.cache/omarchy/wallpaper-editor/`. Sources are never edited or resized on disk. EXIF orientation is applied before requested rotation. Cache eviction retains 32 recent entries where possible while protecting images leased by live frames.

The browser lists immediate readable PNG, JPEG, and WebP files, sorted by filename. It does not recurse into folders. Corrupt thumbnails are marked unreadable and excluded from navigation.

### Legacy portrait migration

When the settings file is absent, this clone recognizes the original author's existing derivative at:

```text
~/.config/omarchy/backgrounds/tokyo-night/winding-road-portrait-2160x3840.jpg
```

If readable, it initializes `DP-3` with that image, Fill, centered position, and **rotation 0**. The derivative is not rotated again. Otherwise monitors follow the shared wallpaper and a nonblocking migration notice is shown. No settings from other wallpaper plugins are imported.

## Update

For a development checkout:

```bash
cd ~/Documents/projects/omarchy-wallpaper-editor
git pull --ff-only
tar --exclude=.git -cf - . | tar -xf - -C ~/.config/omarchy/plugins/suhayb.background
omarchy plugin validate ~/.config/omarchy/plugins/suhayb.background
omarchy restart shell
```

For an installation managed by Omarchy:

```bash
omarchy plugin update suhayb.background
```

Commit or back up local source edits before updating.

## Disable or uninstall

Return background ownership to Omarchy's built-in renderer:

```bash
omarchy plugin disable suhayb.background
```

Omarchy's clone mechanism restores the source plugin when the clone is disabled. Confirm the result with:

```bash
omarchy-shell shell listPlugins
```

For a plugin-manager installation, removal is available after disabling:

```bash
omarchy plugin remove suhayb.background
```

The same plugin-manager removal command can remove a manually installed copy. Keep the separate project checkout if you want to continue development.

Your project checkout, image sources, settings, and cache are separate. Back up settings before intentionally resetting them. Do not remove source images to uninstall the plugin.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| Editor does not open | Confirm `suhayb.background` is enabled, run `omarchy plugin validate <checkout>`, then `omarchy restart shell`. |
| `background editorState` is not found | The clone is not loaded, or another renderer owns that IPC target. Check plugin ownership first. |
| Image cannot be prepared | Check that the source still exists and is readable, and that `magick` and `identify` are installed. |
| Settings are refused | Check for malformed JSON, unsupported schema versions, a symlink at the settings path, wrong ownership, or a file larger than 64 KiB. The last valid in-memory settings are retained. |
| Settings changed externally | Close and reopen the editor to reload. Unsaved drafts are not silently overwritten; Apply stays disabled while conflicted. |
| Wallpaper is not visible | Windows cover the background layer. Test on an empty workspace. |
| Original/Custom unavailable | Inspect `hyprctl monitors -j`; the plugin requires physical dimensions consistent with Qt's logical screen size and scale. |

Read current committed state and monitor metadata:

```bash
omarchy-shell background editorState
```

## Development and verification

```bash
cd ~/Documents/projects/omarchy-wallpaper-editor
node --test tests/*.test.js
python3 -m py_compile scripts/editor-io.py
omarchy plugin validate .
```

The EXIF regression test additionally uses `exiv2` and skips when it is unavailable. Image-preparation tests require ImageMagick.

Behavioral checks cover geometry, schema validation, guarded persistence, immutable preparation, EXIF/rotation ordering, filename transport, and cache leases. Native runtime verification has included live landscape/portrait previews, Apply and restart persistence, isolated corrupt-image recovery, external config conflicts, and virtual-output topology changes. Automated tests do not replace visual verification on your own output layout.

## Project layout

| File | Responsibility |
| --- | --- |
| `Background.qml` | Native service, per-monitor state, IPC, preview timeout, transitions. |
| `EditorOverlay.qml` | Omarchy-styled editor and picker lifecycle. |
| `WallpaperFrame.qml` | Shared physical-pixel rendering geometry and prepared-image lifecycle. |
| `Model.js` | Pure layout, recommendation, and validation functions. |
| `scripts/editor-io.py` | Guarded settings I/O, image discovery, preparation, and cache. |
| `tests/` | Node-driven model and helper behavior tests. |

## Attribution

Derived from Omarchy's native `omarchy.background` plugin. Native shell components and theme behavior belong to the [Omarchy project](https://github.com/basecamp/omarchy). This repository preserves the cloned plugin's provenance and local development history. It is an independent customization, not an official Omarchy plugin.
