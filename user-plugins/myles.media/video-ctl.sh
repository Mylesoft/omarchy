#!/usr/bin/env bash
# mpv PiP control for myles.media video playback.
# Usage: video-ctl.sh <op> [json-params]
set -euo pipefail
op="${1:-}"
params="${2-}"
[[ -n ${params:-} ]] || params='{}'
[[ -n $op ]] || { echo '{"ok":false,"error":"missing-op"}'; exit 1; }

STATE="${HOME}/.local/state/omarchy/media"
SOCK="${STATE}/mpv.sock"
PIDFILE="${STATE}/mpv-pip.pid"
GEOMFILE="${STATE}/video-pip.json"
mkdir -p "$STATE"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 - "$op" "$params" "$SOCK" "$PIDFILE" "$GEOMFILE" "$SCRIPT_DIR" <<'PY'
import json, os, socket, subprocess, sys, time, shutil

op = sys.argv[1]
try:
  params = json.loads(sys.argv[2] if len(sys.argv) > 2 else "{}")
except Exception:
  params = {}
SOCK = sys.argv[3]
PIDFILE = sys.argv[4]
GEOMFILE = sys.argv[5]
SCRIPT_DIR = sys.argv[6] if len(sys.argv) > 6 else os.path.dirname(os.path.abspath(__file__))
INSTANCE = str(params.get("instance") or "").strip()
if INSTANCE:
  import re
  if not re.fullmatch(r"p[2-4]", INSTANCE):
    print(json.dumps({"ok": False, "error": "invalid-instance"}))
    raise SystemExit(2)
  STATE = os.path.dirname(SOCK)
  SOCK = os.path.join(STATE, f"mpv-{INSTANCE}.sock")
  PIDFILE = os.path.join(STATE, f"mpv-{INSTANCE}.pid")
  GEOMFILE = os.path.join(STATE, f"video-{INSTANCE}.json")
PIP_LUA = os.path.join(SCRIPT_DIR, "mpv-pip.lua")

TITLE = "omarchy-media-pip"
APP_ID = "omarchy-media-pip"  # shared rule; each instance is resolved by its PID
DEFAULT_W, DEFAULT_H = 320, 180
MARGIN = 24
MIN_W, MIN_H = 240, 135

VIDEO_EXTS = {".mp4", ".webm", ".mkv", ".avi", ".mov", ".m4v", ".mpeg", ".mpg", ".ts", ".flv"}


def load_geom():
  try:
    with open(GEOMFILE, "r", encoding="utf-8") as f:
      return json.load(f) or {}
  except Exception:
    return {}


def save_geom(data):
  cur = load_geom()
  cur.update(data or {})
  try:
    with open(GEOMFILE, "w", encoding="utf-8") as f:
      json.dump(cur, f, indent=2)
  except Exception:
    pass


def mpv_alive():
  if not os.path.exists(SOCK):
    return False
  try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(0.4)
    s.connect(SOCK)
    s.close()
    return True
  except Exception:
    return False


def ipc(cmd, timeout=3.0):
  """Send JSON IPC command to mpv. cmd is a list like ['get_property','pause']."""
  if not mpv_alive():
    return {"ok": False, "error": "mpv-offline"}
  req = {"command": cmd}
  try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect(SOCK)
    s.sendall((json.dumps(req) + "\n").encode())
    buf = b""
    while True:
      chunk = s.recv(65536)
      if not chunk:
        break
      buf += chunk
      if b"\n" in buf:
        break
    s.close()
    line = buf.split(b"\n", 1)[0].decode("utf-8", "replace")
    return json.loads(line) if line else {"ok": False, "error": "empty"}
  except Exception as e:
    return {"ok": False, "error": str(e)[:200]}


def get_prop(name, default=None):
  r = ipc(["get_property", name])
  if r.get("error") == "success" or "data" in r:
    return r.get("data", default)
  return default


def set_prop(name, value):
  r = ipc(["set_property", name, value])
  return r.get("error") == "success" or r.get("ok") is not False and "error" not in str(r.get("error", ""))


def geometry_string(geom=None):
  g = geom or load_geom()
  w = int(g.get("width") or DEFAULT_W)
  h = int(g.get("height") or DEFAULT_H)
  # Prefer absolute x/y when known; else bottom-right via mpv geometry.
  if "x" in g and "y" in g:
    x, y = int(g["x"]), int(g["y"])
    return f"{w}x{h}+{x}+{y}"
  # Default new PiP windows to the top-left, inside the reserved bar area.
  return f"{w}x{h}+{MARGIN}+{MARGIN}"


def ensure_mpv(path="", title=""):
  if mpv_alive():
    return True
  if os.path.exists(SOCK):
    try:
      os.remove(SOCK)
    except Exception:
      pass
  geom = geometry_string()
  cmd = [
    "mpv",
    "--force-window=immediate",
    "--idle=yes",
    "--keep-open=yes",
    "--ontop",
    "--window-dragging=yes",
    "--no-terminal",
    "--no-border",
    f"--title={TITLE}",
    f"--wayland-app-id={APP_ID}",
    f"--geometry={geom}",
    f"--input-ipc-server={SOCK}",
    "--osc=yes",
    "--osd-level=1",
    "--script-opts=osc-visibility=auto,osc-autohide-delay=2.0,osc-bar-w=95,osc-deadzone=0",
    "--ytdl=yes",
    "--ytdl-format=bestvideo+bestaudio/best",
    "--hwdec=auto-safe",
    "--loop-file=no",
    "--input-default-bindings=yes",
  ]
  if os.path.isfile(PIP_LUA):
    cmd.append(f"--script={PIP_LUA}")
  g0 = load_geom()
  if g0.get("aspectLock") is False:
    # Prefer free resize when unlocked; Hypr rule default is locked.
    pass
  # Start idle; loadfile separately so we can reuse the window.
  try:
    proc = subprocess.Popen(
      cmd,
      stdout=subprocess.DEVNULL,
      stderr=subprocess.DEVNULL,
      start_new_session=True,
    )
  except Exception as e:
    print(json.dumps({"ok": False, "error": f"spawn-failed:{e}"}))
    raise SystemExit(2)
  with open(PIDFILE, "w") as f:
    f.write(str(proc.pid))
  for _ in range(40):
    if mpv_alive():
      return True
    time.sleep(0.05)
  return mpv_alive()


def stop_mpv():
  if mpv_alive():
    ipc(["quit"])
    time.sleep(0.15)
  if os.path.exists(SOCK):
    try:
      os.remove(SOCK)
    except Exception:
      pass
  if os.path.exists(PIDFILE):
    try:
      pid = int(open(PIDFILE).read().strip() or "0")
      if pid:
        os.kill(pid, 15)
    except Exception:
      pass
    try:
      os.remove(PIDFILE)
    except Exception:
      pass
  # Persist geometry from hyprctl if available
  try:
    c = hypr_client()
    if c:
      at = c.get("at") or [0, 0]
      size = c.get("size") or [DEFAULT_W, DEFAULT_H]
      save_geom({"x": int(at[0]), "y": int(at[1]),
                  "width": int(size[0]), "height": int(size[1])})
  except Exception:
    pass
  return True


def hypr_client():
  try:
    r = subprocess.run(
      ["hyprctl", "clients", "-j"],
      capture_output=True, text=True, timeout=2,
    )
    clients = json.loads(r.stdout or "[]")
    try:
      pid = int(open(PIDFILE, encoding="utf-8").read().strip() or "0")
    except Exception:
      pid = 0
    for c in clients:
      if pid and int(c.get("pid") or 0) != pid:
        continue
      cl = str(c.get("class") or "")
      title = str(c.get("title") or "")
      init = str(c.get("initialTitle") or "")
      if cl == APP_ID or title == TITLE or init == TITLE:
        return c
  except Exception:
    pass
  return None


def hypr_address():
  c = hypr_client()
  return str((c or {}).get("address") or "")


def hypr_lua(expr):
  """Run a Hyprland 0.56+ Lua dispatcher expression via hyprctl dispatch."""
  try:
    r = subprocess.run(
      ["hyprctl", "dispatch", expr],
      capture_output=True, text=True, timeout=2,
    )
    out = (r.stdout or "") + (r.stderr or "")
    return r.returncode == 0 and "error" not in out.lower()
  except Exception:
    return False


def hypr_focus(addr=None):
  addr = addr or hypr_address()
  if not addr:
    return False
  return hypr_lua(f'hl.dsp.focus({{ window = "address:{addr}" }})')


def hypr_resize(w, h):
  if not hypr_focus():
    return False
  return hypr_lua(f"hl.dsp.window.resize({{ x = {int(w)}, y = {int(h)}, relative = false }})")


def hypr_move(x, y):
  if not hypr_focus():
    return False
  return hypr_lua(f"hl.dsp.window.move({{ x = {int(x)}, y = {int(y)}, relative = false }})")


def hypr_pin():
  if not hypr_focus():
    return False
  # float(true) sets floating; action="set" toggles on Hyprland 0.56
  hypr_lua("hl.dsp.window.float(true)")
  return hypr_lua("hl.dsp.window.pin()")


def hypr_fullscreen(enable):
  c = hypr_client()
  addr = str((c or {}).get("address") or "")
  if not addr:
    return False
  target = json.dumps(f"address:{addr}")
  # Hyprland blocks fullscreen on pinned windows by default. The PiP is pinned
  # so it floats above other workspaces; temporarily unpin it while fullscreen.
  if enable and c.get("pinned"):
    hypr_lua(f"hl.dsp.window.pin({{ action = 'off', window = {target} }})")
  action = "set" if enable else "unset"
  expr = (f"hl.dsp.window.fullscreen({{ mode = 'fullscreen', action = '{action}', "
          f"layout_aware = false, window = {target} }})")
  hypr_lua(expr)
  # Validate the compositor state; dispatch can return 'ok' even if a pinned
  # window prevented the operation.
  wanted = 2 if enable else 0
  for _ in range(20):
    c = hypr_client()
    try:
      if c and int(c.get("fullscreen") or 0) == wanted:
        if not enable:
          target = json.dumps(f"address:{c.get('address') or addr}")
          hypr_lua(f"hl.dsp.window.float({{ action = 'on', window = {target} }})")
          hypr_lua(f"hl.dsp.window.pin({{ action = 'on', window = {target} }})")
        return True
    except (TypeError, ValueError):
      pass
    time.sleep(0.05)
  # More precise fallback for builds where fullscreen() does not update both
  # compositor and client state together.
  if enable:
    hypr_lua(f"hl.dsp.window.fullscreen_state({{ internal = 2, client = 2, action = 'set', layout_aware = false, window = {target} }})")
    for _ in range(20):
      c = hypr_client()
      if c and int(c.get("fullscreen") or 0) == 2:
        return True
      time.sleep(0.05)
  return False


def hypr_setprop(prop, value):
  if not hypr_focus():
    return False
  # value may be number or string
  if isinstance(value, (int, float)) and not isinstance(value, bool):
    lit = str(value)
  else:
    lit = json.dumps(str(value))
  return hypr_lua(f"hl.dsp.window.set_prop({{ prop = {json.dumps(str(prop))}, value = {lit} }})")


def apply_float_pin():
  """Ensure window is floating + pinned after spawn (rules should also do this)."""
  addr = ""
  for _ in range(60):
    addr = hypr_address()
    if addr:
      break
    time.sleep(0.05)
  if not addr:
    return False
  # Retry float+pin — rules sometimes miss mpv's first map.
  # IMPORTANT: float(true) sets; float({action="set"}) toggles on Hypr 0.56.
  for _ in range(10):
    hypr_focus(addr)
    c = hypr_client()
    if not (c and c.get("floating")):
      hypr_lua("hl.dsp.window.float(true)")
    hypr_lua("hl.dsp.window.pin()")
    c = hypr_client()
    if c and c.get("floating") and c.get("pinned"):
      break
    time.sleep(0.08)
  g = load_geom()
  if g.get("fullscreen"):
    return True
  apply_preset(g.get("lastPreset") or "S")
  # Re-assert pin after resize/move (some ops can drop it)
  c = hypr_client()
  if c and c.get("floating") and not c.get("pinned"):
    hypr_focus()
    hypr_lua("hl.dsp.window.pin()")
  return True


def apply_preset(name):
  name = str(name or "S").upper()
  presets = {
    "S": (320, 180),
    "M": (640, 360),
    "L": (960, 540),
  }
  if name == "FULL" or name == "FULLSCREEN":
    hypr_fullscreen(True)
    save_geom({"lastPreset": "FULL", "fullscreen": True})
    return {"ok": True, "preset": "FULL"}
  if name not in presets:
    name = "S"
  w, h = presets[name]
  prev = load_geom()
  keep_pos = ("x" in prev and "y" in prev and not prev.get("hidden")
              and int(prev.get("x", -9999)) > -2000)
  save_geom({"width": w, "height": h, "lastPreset": name, "fullscreen": False})
  if not hypr_address():
    ipc(["set_property", "geometry", geometry_string()])
    return {"ok": True, "preset": name, "width": w, "height": h}
  hypr_fullscreen(False)
  # Ensure floating before resize — tiled resize ignores PiP geometry
  c = hypr_client()
  if not (c and c.get("floating")):
    hypr_focus()
    hypr_lua("hl.dsp.window.float(true)")
  hypr_resize(w, h)
  if keep_pos:
    hypr_move(int(prev["x"]), int(prev["y"]))
  else:
    try:
      mon = json.loads(subprocess.run(
        ["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=2
      ).stdout or "[]")
      active = next((m for m in mon if m.get("focused")), mon[0] if mon else None)
      if active:
        mx, my = int(active["x"]), int(active["y"])
        mw, mh = int(active["width"]), int(active["height"])
        x = mx + MARGIN
        y = my + MARGIN
        hypr_move(x, y)
        save_geom({"x": x, "y": y, "width": w, "height": h, "snap": "tl"})
    except Exception:
      pass
  return {"ok": True, "preset": name, "width": w, "height": h}


def snap_corner(corner):
  corner = str(corner or "br").lower()
  g = load_geom()
  w = int(g.get("width") or DEFAULT_W)
  h = int(g.get("height") or DEFAULT_H)
  addr = hypr_address()
  if not addr:
    return {"ok": False, "error": "no-window"}
  try:
    mon = json.loads(subprocess.run(
      ["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=2
    ).stdout or "[]")
    active = next((m for m in mon if m.get("focused")), mon[0] if mon else None)
    if not active:
      return {"ok": False, "error": "no-monitor"}
    mx, my = int(active["x"]), int(active["y"])
    mw, mh = int(active["width"]), int(active["height"])
    if corner in ("tl", "top-left"):
      x, y = mx + MARGIN, my + MARGIN
    elif corner in ("tr", "top-right"):
      x, y = mx + mw - w - MARGIN, my + MARGIN
    elif corner in ("bl", "bottom-left"):
      x, y = mx + MARGIN, my + mh - h - MARGIN
    else:
      x, y = mx + mw - w - MARGIN, my + mh - h - MARGIN
    hypr_move(x, y)
    save_geom({"x": x, "y": y, "snap": corner})
    return {"ok": True, "corner": corner, "x": x, "y": y}
  except Exception as e:
    return {"ok": False, "error": str(e)[:160]}


def set_opacity(value):
  try:
    v = float(value)
  except Exception:
    v = 1.0
  v = max(0.4, min(1.0, v))
  save_geom({"opacity": v})
  hypr_setprop("opacity", v)
  return {"ok": True, "opacity": v}


def set_clickthrough(enabled):
  """Pass clicks through the PiP via Hyprland allows_input=0.
  Also no_focus + disable mpv mouse cursor so OSC doesn't eat hover."""
  enabled = bool(enabled)
  save_geom({"clickThrough": enabled})
  # allows_input is the real click-through prop on Hyprland 0.56+
  hypr_setprop("allows_input", "0" if enabled else "1")
  hypr_setprop("no_focus", "1" if enabled else "0")
  # Stop mpv from consuming mouse when pass-through is on
  try:
    set_prop("input-cursor", not enabled)
  except Exception:
    pass
  # Soft visual cue when pass mode is on
  if enabled:
    base = float(load_geom().get("opacity") or 1.0)
    hypr_setprop("opacity", max(0.4, min(0.7, base * 0.85)))
  else:
    hypr_setprop("opacity", float(load_geom().get("opacity") or 1.0))
  return {"ok": True, "clickThrough": enabled}


def set_aspect_lock(enabled):
  enabled = bool(enabled)
  save_geom({"aspectLock": enabled})
  hypr_setprop("keep_aspect_ratio", "1" if enabled else "0")
  return {"ok": True, "aspectLock": enabled}


def capture_geom_meta():
  """Persist monitor / pinned / size from live Hypr client."""
  c = hypr_client()
  if not c:
    return load_geom()
  at = c.get("at") or [0, 0]
  size = c.get("size") or [DEFAULT_W, DEFAULT_H]
  x, y = int(at[0]), int(at[1])
  patch = {
    "pinned": bool(c.get("pinned")),
    "monitor": c.get("monitor"),
  }
  if x > -2000 and y > -2000:
    patch.update({
      "x": x, "y": y,
      "width": max(MIN_W, int(size[0])),
      "height": max(MIN_H, int(size[1])),
    })
  save_geom(patch)
  return load_geom()


def hide_window():
  """Park PiP off-screen while keeping mpv (and last frame) alive."""
  c = hypr_client()
  if c:
    at = c.get("at") or [0, 0]
    size = c.get("size") or [DEFAULT_W, DEFAULT_H]
    x, y = int(at[0]), int(at[1])
    if x > -2000 and y > -2000:
      save_geom({
        "x": x, "y": y,
        "width": max(MIN_W, int(size[0])), "height": max(MIN_H, int(size[1])),
        "hidden": True,
      })
    else:
      save_geom({"hidden": True})
  hypr_move(-4000, -4000)
  return {"ok": True, "hidden": True}


def show_window():
  save_geom({"hidden": False})
  g = load_geom()
  if "x" in g and "y" in g and int(g.get("x", -9999)) > -2000:
    hypr_move(int(g["x"]), int(g["y"]))
    if g.get("width") and g.get("height"):
      hypr_resize(int(g["width"]), int(g["height"]))
  else:
    apply_preset(g.get("lastPreset") or "S")
  return status_payload()


def status_payload():
  online = mpv_alive()
  g = load_geom()
  if not online:
    return {
      "ok": True, "online": False, "playing": False, "paused": True,
      "path": "", "title": "", "position": 0, "length": 0,
      "volume": 1.0, "fullscreen": False, "subs": False,
      "loop": "no", "playlistCount": 0, "playlistPos": -1,
      "aspectLock": g.get("aspectLock", True),
      "clickThrough": bool(g.get("clickThrough")),
      "geometry": g,
    }
  paused = bool(get_prop("pause", True))
  path = str(get_prop("path", "") or "")
  title = str(get_prop("media-title", "") or get_prop("filename/no-ext", "") or "")
  pos = float(get_prop("time-pos", 0) or 0)
  length = float(get_prop("duration", 0) or 0)
  vol = float(get_prop("volume", 100) or 100) / 100.0
  fs = bool(get_prop("fullscreen", False))
  subs = bool(get_prop("sub-visibility", False))
  loop = str(get_prop("loop-file", "no") or "no")
  try:
    pl_count = int(get_prop("playlist-count", 0) or 0)
  except Exception:
    pl_count = 0
  try:
    pl_pos = int(get_prop("playlist-pos", -1) or -1)
  except Exception:
    pl_pos = -1
  return {
    "ok": True,
    "online": True,
    "playing": (not paused) and bool(path),
    "paused": paused,
    "path": path,
    "title": title,
    "position": pos,
    "length": length,
    "volume": max(0.0, min(1.0, vol)),
    "fullscreen": fs,
    "subs": subs,
    "loop": loop,
    "playlistCount": pl_count,
    "playlistPos": pl_pos,
    "aspectLock": g.get("aspectLock", True),
    "clickThrough": bool(g.get("clickThrough")),
    "geometry": g,
  }


# --- ops -------------------------------------------------------------------
if op == "status":
  print(json.dumps(status_payload()))

elif op == "ensure":
  ok = ensure_mpv()
  print(json.dumps({"ok": ok, "online": ok}))

elif op == "play":
  path = str(params.get("path") or "").strip()
  title = str(params.get("title") or "").strip()
  if not path:
    print(json.dumps({"ok": False, "error": "missing-path"}))
    raise SystemExit(2)
  if INSTANCE and not mpv_alive():
    geom_patch = {k: params[k] for k in ("x", "y", "width", "height") if k in params}
    if geom_patch:
      save_geom(geom_patch)
  if not ensure_mpv(path, title):
    print(json.dumps({"ok": False, "error": "mpv-start-failed"}))
    raise SystemExit(2)
  # Replace current file and play
  r = ipc(["loadfile", path, "replace"])
  ipc(["set_property", "pause", False])
  try:
    start = max(0.0, min(float(params.get("start") or 0), 86400.0))
    if start > 2.0:
      ipc(["seek", start, "absolute"])
  except (TypeError, ValueError):
    pass
  if params.get("muted"):
    ipc(["set_property", "mute", True])
    ipc(["set_property", "volume", 0])
  else:
    ipc(["set_property", "mute", False])
  # Only force a human title — never lock in URL stubs / "YouTube · id"
  # so ytdl can populate media-title with the real name.
  tnorm = title.strip().lower()
  stub = (not title) or tnorm in ("video", "videoplayback", "channel", "stream") \
    or tnorm.startswith("youtube ·") or "watch?v=" in tnorm \
    or tnorm.startswith("http://") or tnorm.startswith("https://")
  if title and not stub:
    ipc(["set_property", "force-media-title", title])
  # Re-assert window title for Hyprland matching
  ipc(["set_property", "title", TITLE])
  time.sleep(0.45)
  apply_float_pin()
  time.sleep(0.15)
  apply_float_pin()
  # Restore opacity / click-through / aspect prefs
  g = load_geom()
  if g.get("opacity") is not None:
    set_opacity(g.get("opacity"))
  if g.get("clickThrough"):
    set_clickthrough(True)
  if "aspectLock" in g:
    set_aspect_lock(bool(g.get("aspectLock")))
  else:
    set_aspect_lock(True)
  save_geom({"lastPath": path, "lastTitle": title, "autoOpen": True, "hidden": False})
  capture_geom_meta()
  st = status_payload()
  st["load"] = r
  print(json.dumps(st))

elif op == "pause":
  set_prop("pause", True)
  print(json.dumps(status_payload()))

elif op == "resume":
  # keep-open leaves eof-reached=true at end — seek back so play resumes
  if bool(get_prop("eof-reached", False)):
    ipc(["seek", 0, "absolute"])
  set_prop("pause", False)
  print(json.dumps(status_payload()))

elif op == "playPause" or op == "toggle":
  cur = bool(get_prop("pause", True))
  set_prop("pause", not cur)
  print(json.dumps(status_payload()))

elif op == "stop":
  stop_mpv()
  print(json.dumps({"ok": True, "online": False, "playing": False}))

elif op == "hide":
  print(json.dumps(hide_window()))

elif op == "show":
  ensure_mpv()
  print(json.dumps(show_window()))

elif op == "seek":
  value = float(params.get("value") or params.get("seconds") or 0)
  absolute = bool(params.get("absolute", True))
  if absolute:
    ipc(["seek", value, "absolute"])
  else:
    ipc(["seek", value, "relative"])
  print(json.dumps(status_payload()))

elif op == "volume":
  # Accept linear 0..1
  try:
    linear = float(params.get("value"))
  except Exception:
    linear = 1.0
  linear = max(0.0, min(1.0, linear))
  set_prop("volume", linear * 100.0)
  print(json.dumps(status_payload()))

elif op == "preset":
  print(json.dumps(apply_preset(params.get("name") or "S")))

elif op == "snap":
  print(json.dumps(snap_corner(params.get("corner") or "br")))

elif op == "opacity":
  print(json.dumps(set_opacity(params.get("value") or 1.0)))

elif op == "clickThrough":
  print(json.dumps(set_clickthrough(params.get("enabled", True))))

elif op == "subs" or op == "subtitles":
  cur = bool(get_prop("sub-visibility", False))
  nxt = not cur if params.get("toggle", True) else bool(params.get("enabled", True))
  set_prop("sub-visibility", nxt)
  print(json.dumps({"ok": True, "subs": nxt}))

elif op == "fullscreen":
  client = hypr_client() or {}
  cur = int(client.get("fullscreen") or 0) == 2
  if not cur:
    cur = bool(get_prop("fullscreen", False)) or bool(load_geom().get("fullscreen"))
  nxt = not cur if params.get("toggle", False) else bool(params.get("enabled", True))
  # A fullscreen request always brings a dismissed/off-screen PiP back first.
  if nxt:
    show_window()
    save_geom({"hidden": False})
  # The PiP is pinned by design. Hyprland will reject fullscreen until it is
  # temporarily unpinned, so use the targeted compositor path and verify it.
  if not hypr_fullscreen(nxt):
    print(json.dumps({"ok": False, "error": "fullscreen-failed", "fullscreen": cur}))
    raise SystemExit(2)
  set_prop("fullscreen", nxt)
  save_geom({"fullscreen": nxt})
  if not nxt:
    save_geom({"hidden": False})
    apply_preset(load_geom().get("lastPreset") or "S")
  print(json.dumps({"ok": True, "fullscreen": nxt, **{k: status_payload()[k] for k in ("online", "playing", "paused", "path", "title", "position", "length", "volume", "subs", "loop", "playlistCount", "playlistPos", "geometry")}}))

elif op == "loop":
  # cycle: no -> inf -> no  (single-file video)
  mode = str(params.get("mode") or "").lower()
  if not mode or mode == "toggle":
    cur = str(get_prop("loop-file", "no") or "no")
    mode = "inf" if cur in ("no", "False", "false", "0") else "no"
  set_prop("loop-file", mode)
  print(json.dumps({"ok": True, "loop": mode, **{k: status_payload()[k] for k in ("playing", "online")}}))

elif op == "geometry-save":
  g = capture_geom_meta()
  if hypr_client():
    print(json.dumps({"ok": True, "geometry": g}))
  else:
    print(json.dumps({"ok": False, "error": "window-not-found", "geometry": g}))
    raise SystemExit(2)

elif op == "persist":
  g = load_geom()
  g.update(params)
  save_geom(g)
  print(json.dumps({"ok": True, "geometry": load_geom()}))

elif op == "aspectLock":
  enabled = params.get("enabled")
  if enabled is None and params.get("toggle"):
    enabled = not bool(load_geom().get("aspectLock", True))
  print(json.dumps(set_aspect_lock(bool(enabled if enabled is not None else True))))

elif op == "queue" or op == "enqueue":
  path = str(params.get("path") or "").strip()
  if not path:
    print(json.dumps({"ok": False, "error": "missing-path"}))
    raise SystemExit(2)
  if not ensure_mpv():
    print(json.dumps({"ok": False, "error": "mpv-start-failed"}))
    raise SystemExit(2)
  mode = str(params.get("mode") or "append")  # append | append-play | replace
  if mode not in ("append", "append-play", "replace"):
    mode = "append"
  r = ipc(["loadfile", path, mode])
  title = str(params.get("title") or "").strip()
  if mode in ("append", "append-play"):
    # Don't lock the whole playlist to this title.
    pass
  elif title and mode == "replace":
    tnorm = title.strip().lower()
    stub = (not title) or tnorm in ("video", "videoplayback") or tnorm.startswith("youtube ·")
    if not stub:
      ipc(["set_property", "force-media-title", title])
  print(json.dumps({"ok": True, "load": r, **{k: status_payload()[k] for k in ("playlistCount", "playlistPos", "path", "online")}}))

elif op == "playlistNext" or op == "playlist-next":
  # Drop any forced title so the next file's media-title can surface.
  try:
    ipc(["set_property", "force-media-title", ""])
  except Exception:
    pass
  r = ipc(["playlist-next", "force"])
  time.sleep(0.15)
  print(json.dumps({"ok": True, "result": r, **status_payload()}))

elif op == "playlistPrev" or op == "playlist-prev":
  try:
    ipc(["set_property", "force-media-title", ""])
  except Exception:
    pass
  r = ipc(["playlist-prev", "force"])
  time.sleep(0.15)
  print(json.dumps({"ok": True, "result": r, **status_payload()}))

elif op == "playlistClear" or op == "playlist-clear":
  ipc(["playlist-clear"])
  print(json.dumps({"ok": True, **status_payload()}))

elif op == "ffprobe":
  path = str(params.get("path") or "").strip()
  if not path or path.startswith("http://") or path.startswith("https://") or "://" in path:
    # Remote / URL — leave to extension/provider heuristics
    print(json.dumps({"ok": True, "video": None, "skipped": True}))
  else:
    video = False
    try:
      r = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=codec_type", "-of", "csv=p=0", path],
        capture_output=True, text=True, timeout=4,
      )
      video = "video" in (r.stdout or "").lower()
    except Exception as e:
      print(json.dumps({"ok": False, "error": str(e)[:160], "video": None}))
      raise SystemExit(0)
    print(json.dumps({"ok": True, "video": video, "path": path}))

else:
  print(json.dumps({"ok": False, "error": f"unknown-op:{op}"}))
  raise SystemExit(1)
PY
