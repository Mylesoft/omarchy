#!/usr/bin/env bash
# Thin cliamp remote helpers for the media panel.
# Usage: cliamp-ctl.sh <op> [json-params]
set -euo pipefail
op="${1:-}"
# IMPORTANT: do not use ${2:-{}} — bash treats the final } as literal and
# corrupts JSON args into {"value":1.25}} which silently falls back to defaults.
params="${2-}"
[[ -n ${params:-} ]] || params='{}'
[[ -n $op ]] || { echo '{"ok":false,"error":"missing-op"}'; exit 1; }

python3 - "$op" "$params" <<'PY'
import json, os, subprocess, shutil, sys

op = sys.argv[1] if len(sys.argv) > 1 else ""
try:
  params = json.loads(sys.argv[2] if len(sys.argv) > 2 else "{}")
except Exception:
  params = {}

def call(operation, p=None, timeout=45):
  cmd = ["cliamp", "remote", "call", operation, "--params", json.dumps(p or {}), "--wait"]
  try:
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    out = (r.stdout or "").strip()
    if not out:
      return {"ok": False, "error": ((r.stderr or "")[:200] or f"empty-stdout exit={r.returncode}")}
    return json.loads(out)
  except Exception as e:
    return {"ok": False, "error": str(e)[:200]}

def result(d):
  job = d.get("job") or {}
  res = job.get("result") if isinstance(job.get("result"), dict) else {}
  snap = job.get("snapshot") or {}
  ok = job.get("state") == "succeeded" or res.get("ok") is True or d.get("ok") is True
  err = str(d.get("error") or job.get("error") or "")
  return ok, res, snap, err

if op == "lyrics":
  d = call("lyrics", {}, timeout=60)
  ok, res, snap, err = result(d)
  lines = res.get("lyrics") or []
  text = "\n".join(
    (f"[{int(x.get('start',0)//60):02d}:{int(x.get('start',0)%60):02d}] " if isinstance(x, dict) and x.get("start") is not None else "")
    + str((x.get("text") if isinstance(x, dict) else x) or "")
    for x in lines
  )
  print(json.dumps({"ok": ok, "lyrics": lines, "text": text, "error": err}))
elif op == "speed":
  value = float(params.get("value", 1.0))
  d = call("speed", {"value": value})
  ok, res, snap, err = result(d)
  speed = res.get("speed")
  if speed is None and isinstance(snap, dict):
    speed = snap.get("speed")
  if speed is None:
    speed = value
  print(json.dumps({"ok": ok, "speed": float(speed), "error": err}))
elif op == "eq":
  name = str(params.get("name") or "Flat")
  d = call("eq", {"name": name})
  ok, res, snap, err = result(d)
  eq = res.get("eq_preset") or res.get("eq")
  if not eq and isinstance(snap, dict):
    eq = snap.get("eq_preset")
  print(json.dumps({"ok": ok, "eq": str(eq or name), "error": err}))
elif op == "eq-list":
  # Known-good cliamp EQ presets (probed once offline). Avoid live probing —
  # it briefly switches EQ while music plays.
  presets = ["Flat", "Rock", "Pop", "Jazz", "Classical", "Vocal", "Loudness", "Electronic", "Acoustic"]
  cur = "Flat"
  try:
    r = subprocess.run(["cliamp", "remote", "state"], capture_output=True, text=True, timeout=5)
    snap = json.loads(r.stdout or "{}")
    s = snap.get("snapshot") or snap
    cur = str(s.get("eq_preset") or "Flat")
  except Exception:
    pass
  print(json.dumps({"ok": True, "presets": presets, "current": cur}))
elif op == "devices":
  d = call("device", {"name": "list"})
  ok, res, snap, err = result(d)
  devices = res.get("devices") or []
  # Normalize + mark active from snapshot when missing
  active = ""
  if isinstance(snap, dict):
    active = str(snap.get("device") or "")
  out = []
  for dev in devices:
    if isinstance(dev, str):
      out.append({"name": dev, "active": dev == active})
    elif isinstance(dev, dict):
      name = str(dev.get("name") or dev.get("id") or "")
      is_active = bool(dev.get("active")) or (name == active)
      out.append({"name": name, "active": is_active})
  print(json.dumps({"ok": ok, "devices": out, "active": active, "error": err}))
elif op == "device":
  name = str(params.get("name") or "").strip()
  d = call("device", {"name": name})
  ok, res, snap, err = result(d)
  active = ""
  if isinstance(snap, dict):
    active = str(snap.get("device") or "")
  print(json.dumps({"ok": ok, "device": name or active, "active": active, "error": err}))
elif op == "queue-path":
  path = str(params.get("path") or "")
  d = call("queue", {"path": path})
  ok, res, snap, err = result(d)
  print(json.dumps({"ok": ok, "error": err}))
elif op == "sinks":
  # PipeWire sinks via wpctl for cast/output UI
  sinks = []
  if shutil.which("wpctl"):
    try:
      p = subprocess.run(["wpctl", "status"], capture_output=True, text=True, timeout=5)
      in_sinks = False
      import re
      for line in (p.stdout or "").splitlines():
        if "Sinks:" in line:
          in_sinks = True
          continue
        if in_sinks and ("Sources:" in line or line.strip().startswith("├─ Sources") or line.strip().startswith("└─ Sources")):
          break
        if in_sinks:
          m = re.search(r"(\d+)\.\s+(.+?)(?:\s+\[vol:.*\])?$", line.strip(" │*├└─"))
          if m:
            sinks.append({
              "id": m.group(1),
              "name": m.group(2).strip(),
              "active": "*" in line,
            })
    except Exception:
      pass
  print(json.dumps({"ok": True, "sinks": sinks}))
elif op == "set-sink":
  sid = str(params.get("id") or "")
  ok = False
  err = ""
  if sid and shutil.which("wpctl"):
    try:
      r = subprocess.run(["wpctl", "set-default", sid], capture_output=True, text=True, timeout=5)
      ok = r.returncode == 0
      err = (r.stderr or "")[:120]
    except Exception as e:
      err = str(e)[:120]
  print(json.dumps({"ok": ok, "error": err}))
elif op == "shuffle":
  name = str(params.get("name") or "toggle")
  d = call("shuffle", {"name": name})
  ok, res, snap, err = result(d)
  shuffle = res.get("shuffle")
  if shuffle is None and isinstance(snap, dict):
    shuffle = snap.get("shuffle")
  print(json.dumps({"ok": ok, "shuffle": bool(shuffle), "error": err}))
elif op == "repeat":
  name = str(params.get("name") or "cycle")
  d = call("repeat", {"name": name})
  ok, res, snap, err = result(d)
  mode = res.get("repeat")
  if mode is None and isinstance(snap, dict):
    mode = snap.get("repeat")
  print(json.dumps({"ok": ok, "repeat": str(mode or "Off"), "error": err}))
elif op == "queue-list":
  offset = int(params.get("offset") or 0)
  limit = int(params.get("limit") or 40)
  d = call("queue.list", {"offset": offset, "limit": limit})
  ok, res, snap, err = result(d)
  tracks = res.get("tracks") or []
  print(json.dumps({
    "ok": ok,
    "index": int(res.get("index") or 0),
    "total": int(res.get("total") or len(tracks)),
    "tracks": tracks,
    "error": err,
  }))
elif op == "queue-play":
  idx = int(params.get("index") or 0)
  d = call("queue.play", {"index": idx})
  ok, res, snap, err = result(d)
  print(json.dumps({"ok": ok, "index": idx, "error": err}))
elif op == "queue-clear":
  d = call("queue.clear", {})
  ok, res, snap, err = result(d)
  print(json.dumps({"ok": ok, "error": err}))
elif op == "queue-remove":
  idx = int(params.get("index", -1))
  d = call("queue.remove", {"index": idx})
  ok, res, snap, err = result(d)
  print(json.dumps({"ok": ok, "index": idx, "error": err}))
elif op == "queue-move":
  idx = int(params.get("index", 0))
  to = int(params.get("to", 0))
  d = call("queue.move", {"index": idx, "to": to})
  ok, res, snap, err = result(d)
  print(json.dumps({"ok": ok, "index": idx, "to": to, "error": err}))
elif op == "queue-enqueue":
  # Play-next: move live track into the play-next lane (or append path).
  idx = params.get("index")
  path = str(params.get("path") or "")
  if idx is not None and str(idx) != "":
    d = call("queue.enqueue", {"index": int(idx)})
  elif path:
    d = call("queue", {"path": path})
  else:
    print(json.dumps({"ok": False, "error": "missing-index-or-path"}))
    raise SystemExit(0)
  ok, res, snap, err = result(d)
  print(json.dumps({"ok": ok, "error": err}))
elif op == "seek-absolute":
  try:
    value = float(params.get("value", params.get("seconds", 0)))
  except Exception:
    value = 0.0
  d = call("seek.absolute", {"value": value})
  ok, res, snap, err = result(d)
  pos = None
  if isinstance(snap, dict):
    pos = snap.get("position")
    if pos is None and isinstance(snap.get("logical_track"), dict):
      pos = snap["logical_track"].get("position")
  print(json.dumps({"ok": ok, "position": pos if pos is not None else value, "error": err}))
elif op == "seek-relative":
  try:
    value = float(params.get("value", params.get("seconds", 0)))
  except Exception:
    value = 0.0
  d = call("seek", {"value": value})
  ok, res, snap, err = result(d)
  print(json.dumps({"ok": ok, "error": err}))
elif op == "provider-search":
  provider = str(params.get("provider") or "spotify").strip()
  query = str(params.get("query") or "").strip()
  limit = max(1, min(20, int(params.get("limit") or 10)))
  d = call("provider.search", {"provider": provider, "query": query, "limit": limit}, timeout=60)
  ok, res, snap, err = result(d)
  tracks = res.get("tracks") or res.get("items") or res.get("results") or []
  print(json.dumps({"ok": ok, "tracks": tracks, "provider": provider, "error": err, "total": len(tracks) if isinstance(tracks, list) else 0}))
elif op == "volume":
  # UI sends linear 0..1; cliamp remote expects dB in [-30, +6].
  DB_MIN, DB_MAX = -30.0, 6.0
  def linear_to_db(v):
    v = max(0.0, min(1.0, float(v)))
    return v * (DB_MAX - DB_MIN) + DB_MIN
  def db_to_linear(db):
    if db is None:
      return (0.0 - DB_MIN) / (DB_MAX - DB_MIN)
    db = max(DB_MIN, min(DB_MAX, float(db)))
    return (db - DB_MIN) / (DB_MAX - DB_MIN)
  try:
    linear = float(params.get("value"))
  except Exception:
    linear = db_to_linear(0)
  linear = max(0.0, min(1.0, linear))
  db = linear_to_db(linear)
  d = call("volume", {"value": db})
  ok, res, snap, err = result(d)
  vol_db = res.get("volume")
  if vol_db is None and isinstance(snap, dict) and "volume" in snap:
    vol_db = snap.get("volume")
  if vol_db is None:
    vol_db = db
  try:
    vol_db = float(vol_db)
  except Exception:
    vol_db = db
  print(json.dumps({
    "ok": ok,
    "volume": round(db_to_linear(vol_db), 4),
    "volumeDb": vol_db,
    "error": err
  }))
elif op == "pause":
  d = call("pause", {})
  ok, res, snap, err = result(d)
  print(json.dumps({"ok": ok, "error": err}))
else:
  print(json.dumps({"ok": False, "error": "unknown-op"}))
PY
