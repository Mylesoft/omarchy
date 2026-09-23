#!/usr/bin/env bash
# Share current station/track (privacy-friendly single link) or full library export.
# Usage:
#   share-station.sh                     # export full library bundle (legacy)
#   share-station.sh --current '<json>'  # copy single station/track URL
set -euo pipefail
STATE="${HOME}/.local/state/omarchy/media"
mkdir -p "$STATE"

if [[ ${1:-} == "--current" ]]; then
  payload="${2-}"
  [[ -n ${payload:-} ]] || payload='{}'
  python3 - "$payload" <<'PY'
import json, sys, subprocess, re
try:
  hit = json.loads(sys.argv[1] if len(sys.argv) > 1 else "{}")
except Exception:
  hit = {}
title = str(hit.get("title") or "Station").strip()
artist = str(hit.get("artist") or "").strip()
path = str(hit.get("path") or "").strip()
garden = str(hit.get("gardenUrl") or "").strip()
if not garden and "radio.garden" in path and "/listen/" in path:
  m = re.search(r"/listen/([A-Za-z0-9_-]+)", path)
  if m:
    garden = "https://radio.garden/listen/" + m.group(1)
# Prefer public pages over raw stream / file paths.
share = garden or ""
if not share and path.startswith("spotify:"):
  # spotify:track:ID → open.spotify.com
  m = re.match(r"spotify:track:([A-Za-z0-9]+)", path)
  share = ("https://open.spotify.com/track/" + m.group(1)) if m else path
elif not share and (path.startswith("http://") or path.startswith("https://")):
  share = path
elif not share and path.startswith("ytsearch"):
  share = "https://www.youtube.com/results?search_query=" + path.split(":", 1)[-1]
elif not share and path and not path.startswith("/"):
  share = path
if not share:
  # Title-only fallback still copies something useful.
  share = title + ((" — " + artist) if artist else "")
if not share:
  print(json.dumps({"ok": False, "error": "nothing-to-share", "mode": "current"}))
  raise SystemExit(0)
text = title + ((" — " + artist) if artist else "")
if share and share != text:
  text = text + "\n" + share
clipboard = False
try:
  # Never block the Share button on a stuck clipboard daemon.
  # --paste-once --foreground exits after one paste (or timeout).
  r = subprocess.run(
    ["timeout", "-k", "0.4s", "0.8s", "wl-copy", "--paste-once", "--foreground"],
    input=text.encode(),
    check=False,
    timeout=1.5,
  )
  clipboard = (r.returncode == 0)
except Exception:
  clipboard = False
print(json.dumps({
  "ok": True,
  "mode": "current",
  "url": share,
  "title": title,
  "clipboard": clipboard,
  "path": share,
}))
PY
  exit 0
fi

OUT="${1:-${HOME}/Downloads/myles-media-station-$(date +%Y%m%d-%H%M%S).json}"
mkdir -p "$(dirname "$OUT")"

python3 - "$STATE" "$OUT" <<'PY'
import json, sys
from pathlib import Path
from datetime import datetime, timezone

state = Path(sys.argv[1])
out = Path(sys.argv[2])

def load(name, default):
  p = state / name
  try:
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else default
  except Exception:
    return default

bundle = {
  "kind": "myles.media.station",
  "version": 1,
  "exportedAt": datetime.now(timezone.utc).isoformat(),
  "favourites": load("favourites.json", {"version": 1, "items": []}),
  "recents": load("recents.json", {"version": 1, "items": []}),
  "folders": load("favourite-folders.json", {"version": 1, "folders": []}),
}
out.write_text(json.dumps(bundle, indent=2), encoding="utf-8")

clipboard = False
try:
  import subprocess
  r = subprocess.run(
    ["timeout", "-k", "0.4s", "0.8s", "wl-copy", "--paste-once", "--foreground"],
    input=out.read_bytes(),
    check=False,
    timeout=1.5,
  )
  clipboard = (r.returncode == 0)
except Exception:
  clipboard = False

print(json.dumps({"ok": True, "path": str(out), "clipboard": clipboard, "mode": "library"}))
PY
