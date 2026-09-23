#!/usr/bin/env bash
# Probe favourite links and mark broken items.
# Usage: verify-favourites.sh <favourites.json>
set -euo pipefail
file="${1:-}"
if [[ -z $file || ! -f $file ]]; then
  printf '%s\n' '{"ok":false,"error":"missing-favourites","items":[],"broken":0}'
  exit 0
fi
export FAV_FILE="$file"
python3 <<'PY'
import json, os, subprocess, urllib.request, shutil

path = os.environ["FAV_FILE"]
try:
  with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
except Exception:
  print(json.dumps({"ok": False, "error": "bad-json", "items": [], "broken": 0}))
  raise SystemExit(0)

items = data.get("items") if isinstance(data, dict) else []
if not isinstance(items, list):
  items = []

def http_ok(url, timeout=8):
  try:
    req = urllib.request.Request(url, method="HEAD", headers={
      "User-Agent": "myles.media/1.0",
      "Referer": "https://radio.garden/",
    })
    with urllib.request.urlopen(req, timeout=timeout) as r:
      return 200 <= getattr(r, "status", 200) < 400
  except Exception:
    try:
      req = urllib.request.Request(url, headers={"User-Agent": "myles.media/1.0"})
      with urllib.request.urlopen(req, timeout=timeout) as r:
        return 200 <= getattr(r, "status", 200) < 400
    except Exception:
      return False

def check(item):
  hit = item.get("hit") or {}
  prov = str(hit.get("provider") or "").lower()
  kind = str(hit.get("kind") or "").lower()
  url = str(hit.get("path") or "")
  if prov == "spotify" or kind == "spotify-track":
    if url.startswith("spotify:track:") or str(hit.get("isrc") or "").strip():
      return True
    return False
  if prov == "youtube" or kind == "youtube":
    if not url:
      return False
    if not shutil.which("yt-dlp"):
      return True  # can't verify — don't mark broken
    try:
      p = subprocess.run(
        ["yt-dlp", "--print", "id", "--no-warnings", "--socket-timeout", "8", url],
        capture_output=True, text=True, timeout=20,
      )
      return p.returncode == 0 and bool((p.stdout or "").strip())
    except Exception:
      return False
  if url.startswith("http://") or url.startswith("https://"):
    return http_ok(url)
  if url:
    return os.path.exists(url) or url.startswith("file:")
  return False

broken = 0
import time
now = time.time()
out = []
for it in items:
  if not isinstance(it, dict):
    continue
  ok = check(it)
  row = dict(it)
  row["broken"] = not ok
  if ok:
    row["lastOkAt"] = now
    broken += 0
  else:
    broken += 1
  out.append(row)

result = {"version": 1, "items": out}
with open(path, "w", encoding="utf-8") as f:
  json.dump(result, f, indent=2)

print(json.dumps({"ok": True, "items": out, "broken": broken, "total": len(out)}))
PY
