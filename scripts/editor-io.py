#!/usr/bin/python3
"""Guarded config, image listing, and immutable oriented wallpaper cache."""
import hashlib, json, os, shutil, stat, subprocess, sys, tempfile

MAX_BYTES = 65536
CONFIG = os.path.join(os.environ.get("HOME", ""), ".config/omarchy/background-editor.json")
BASE = os.path.dirname(CONFIG)
CACHE = os.path.join(os.environ.get("HOME", ""), ".cache/omarchy/wallpaper-editor")

def fail(message):
    print("editor-io: " + str(message), file=sys.stderr)
    return 1

def checked_target(path, must_exist=False):
    parent = os.path.dirname(path)
    if os.path.abspath(path) != path or path != CONFIG or os.path.realpath(parent) != parent:
        raise ValueError("config path escapes or traverses symlinks outside ~/.config/omarchy")
    directory = os.stat(parent, follow_symlinks=False)
    if not stat.S_ISDIR(directory.st_mode) or directory.st_uid != os.geteuid():
        raise ValueError("config directory type or owner refused")
    if os.path.islink(path): raise ValueError("refusing symlink at target")
    if not os.path.lexists(path):
        if must_exist: raise ValueError("not a regular file")
        return None
    st = os.lstat(path)
    if not stat.S_ISREG(st.st_mode) or st.st_uid != os.geteuid() or st.st_size > MAX_BYTES:
        raise ValueError("config target type, owner, or size refused")
    return st

def read_config():
    checked_target(CONFIG)
    if not os.path.exists(CONFIG):
        legacy = os.path.join(os.environ.get("HOME", ""), ".config/omarchy/backgrounds/tokyo-night/winding-road-portrait-2160x3840.jpg")
        if os.path.isfile(legacy) and os.access(legacy, os.R_OK):
            print(json.dumps({"version": 1, "monitors": {"DP-3": {"image": legacy, "mode": "fill", "rotation": 0, "anchorX": 0.5, "anchorY": 0.5, "widthPx": 2160, "heightPx": 3840}}, "missing": True}, ensure_ascii=False))
        else:
            print(json.dumps({"version": 1, "monitors": {}, "missing": True, "migrationNotice": "The former DP-3 wallpaper is unavailable; using the shared wallpaper."}))
        return 0
    fd = os.open(CONFIG, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as f: data = f.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES: raise ValueError("config exceeds 64 KiB")
    value = json.loads(data.decode("utf-8"))
    if not isinstance(value, dict) or value.get("version") != 1 or not isinstance(value.get("monitors"), dict):
        raise ValueError("unsupported config schema")
    print(json.dumps(value, ensure_ascii=False))
    return 0

def write_config(payload):
    value = json.loads(payload)
    if not isinstance(value, dict) or value.get("version") != 1 or not isinstance(value.get("monitors"), dict):
        raise ValueError("unsupported config schema")
    if len(payload.encode("utf-8")) > MAX_BYTES: raise ValueError("payload exceeds 64 KiB")
    checked_target(CONFIG)
    fd, tmp = tempfile.mkstemp(dir=BASE, prefix=".background-editor.")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write((json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")); f.flush(); os.fsync(f.fileno())
        os.replace(tmp, CONFIG)
        dfd = os.open(BASE, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try: os.fsync(dfd)
        finally: os.close(dfd)
    except Exception:
        try: os.unlink(tmp)
        except OSError: pass
        raise
    print('{"ok":true}')
    return 0

def images(directory):
    if os.path.islink(directory) or not os.path.isdir(directory): raise ValueError("not a readable directory")
    allowed = {".png", ".jpg", ".jpeg", ".webp"}
    result = []
    with os.scandir(directory) as entries:
        for entry in entries:
            try:
                if os.path.splitext(entry.name)[1].lower() in allowed and entry.is_file(follow_symlinks=False) and os.access(entry.path, os.R_OK):
                    result.append(os.path.abspath(entry.path))
            except OSError: pass
    result.sort(key=lambda p: (os.path.basename(p).casefold(), p))
    print(json.dumps(result, ensure_ascii=False))
    return 0

def cache_paths():
    protected = set()
    for name in os.listdir(CACHE):
        if not name.startswith(".lease-") or not name.endswith(".json"): continue
        lease_path = os.path.join(CACHE, name)
        try:
            with open(lease_path, "r", encoding="utf-8") as stream: lease = json.load(stream)
            pid = int(lease["pid"])
            os.kill(pid, 0)
            for path in lease.get("paths", []):
                if isinstance(path, str) and os.path.dirname(path) == CACHE and path.endswith(".png"): protected.add(path)
        except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
            try: os.unlink(lease_path)
            except OSError: pass
    return protected

def write_lease(owner, paths):
    if not owner: return
    pid = os.getppid()
    suffix = hashlib.sha256(owner.encode("utf-8")).hexdigest()[:24]
    target = os.path.join(CACHE, ".lease-%d-%s.json" % (pid, suffix))
    valid = [path for path in paths if isinstance(path, str) and os.path.dirname(path) == CACHE and path.endswith(".png") and os.path.isfile(path)]
    fd, tmp = tempfile.mkstemp(dir=CACHE, prefix=".lease.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump({"pid": pid, "paths": valid}, stream); stream.flush(); os.fsync(stream.fileno())
        os.replace(tmp, target)
    except Exception:
        try: os.unlink(tmp)
        except OSError: pass
        raise

def cache_lock():
    os.makedirs(CACHE, mode=0o700, exist_ok=True)
    import fcntl
    fd = os.open(os.path.join(CACHE, ".prepare.lock"), os.O_CREAT | os.O_RDWR, 0o600)
    fcntl.flock(fd, fcntl.LOCK_EX)
    return fd, fcntl

def prune_cache(protected):
    files = []
    for name in os.listdir(CACHE):
        if not name.endswith(".png"): continue
        path = os.path.join(CACHE, name)
        try:
            info = os.lstat(path)
            if stat.S_ISREG(info.st_mode): files.append((info.st_mtime_ns, path))
        except OSError: pass
    files.sort()
    remaining = len(files)
    for _, path in files:
        if remaining <= 32: break
        if path in protected: continue
        try: os.unlink(path); remaining -= 1
        except OSError: pass

def update_lease(owner, payload):
    values = json.loads(payload)
    if not isinstance(values, list): raise ValueError("cache lease must be a JSON array")
    fd, fcntl = cache_lock()
    try:
        if owner and not values:
            suffix = hashlib.sha256(owner.encode("utf-8")).hexdigest()[:24]
            lease = os.path.join(CACHE, ".lease-%d-%s.json" % (os.getppid(), suffix))
            try: os.unlink(lease)
            except FileNotFoundError: pass
        else: write_lease(owner, values)
        prune_cache(cache_paths())
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN); os.close(fd)
    print('{"ok":true}')
    return 0

def prepare(path, rotation, owner="", previous=""):
    if not os.path.isabs(path) or rotation not in (0, 90, 180, 270): raise ValueError("invalid prepare arguments")
    if not shutil.which("magick") or not shutil.which("identify"):
        raise ValueError("ImageMagick is unavailable; expected magick and identify")
    lock_fd, fcntl = cache_lock()
    try:
        return prepare_locked(path, rotation, owner, previous)
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)

def prepare_locked(path, rotation, owner="", previous=""):
    canonical = os.path.realpath(path)
    st = os.stat(canonical, follow_symlinks=False)
    if not stat.S_ISREG(st.st_mode) or not os.access(canonical, os.R_OK): raise ValueError("image is not a readable regular file")
    key = hashlib.sha256((canonical + "\0%d\0%d\0%d" % (st.st_size, st.st_mtime_ns, rotation)).encode()).hexdigest()
    target = os.path.join(CACHE, key + ".png")
    if not os.path.isfile(target):
        fd, tmp = tempfile.mkstemp(dir=CACHE, prefix=".prepare.", suffix=".png"); os.close(fd)
        try:
            transform = {0: [], 90: ["-rotate", "90"], 180: ["-rotate", "180"], 270: ["-rotate", "-90"]}[rotation]
            subprocess.run(["magick", canonical + "[0]", "-auto-orient"] + transform + ["+repage", tmp], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            os.replace(tmp, target)
        except Exception:
            try: os.unlink(tmp)
            except OSError: pass
            raise
    identify = subprocess.run(["identify", "-format", "%w %h", target], check=True, capture_output=True, text=True)
    width, height = map(int, identify.stdout.split())
    os.utime(target, None)
    if owner: write_lease(owner, [target, previous])
    protected = cache_paths()
    protected.add(target)
    prune_cache(protected)
    print(json.dumps({"path": target, "width": width, "height": height}))
    return 0

def main(argv):
    try:
        if len(argv) == 2 and argv[1] == "read": return read_config()
        if len(argv) == 3 and argv[1] == "write": return write_config(argv[2])
        if len(argv) == 3 and argv[1] == "images": return images(argv[2])
        if len(argv) in (4, 6) and argv[1] == "prepare": return prepare(argv[2], int(argv[3]), argv[4] if len(argv) == 6 else "", argv[5] if len(argv) == 6 else "")
        if len(argv) == 4 and argv[1] == "lease": return update_lease(argv[2], argv[3])
        return fail("usage: editor-io.py read | write <json> | images <directory> | prepare <absolute-path> <rotation> [owner previous-path] | lease <owner> <json-path-array>")
    except Exception as error: return fail(error)

if __name__ == "__main__": sys.exit(main(sys.argv))
