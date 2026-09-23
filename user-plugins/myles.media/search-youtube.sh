#!/usr/bin/env bash
# YouTube search via yt-dlp → JSON hits for the media panel.
set -euo pipefail
query="${1:-}"
limit="${2:-10}"
[[ -n $query ]] || { echo '{"ok":true,"provider":"youtube","tracks":[],"total":0}'; exit 0; }

export YT_SEARCH_QUERY="$query"
export YT_SEARCH_LIMIT="$limit"

python3 <<'PY'
import json, os, subprocess, shutil

query = os.environ["YT_SEARCH_QUERY"]
limit = max(1, min(20, int(os.environ["YT_SEARCH_LIMIT"])))

if not shutil.which("yt-dlp"):
  print(json.dumps({"ok": False, "error": "yt-dlp-missing", "provider": "youtube", "tracks": [], "total": 0}))
  raise SystemExit(0)

cmd = [
  "yt-dlp",
  f"ytsearch{limit}:{query}",
  "--flat-playlist",
  "--no-warnings",
  "--print", "%(.{id,title,uploader,channel,webpage_url,url,duration,thumbnails})j",
]
try:
  p = subprocess.run(cmd, capture_output=True, text=True, timeout=45)
except Exception as e:
  print(json.dumps({"ok": False, "error": str(e)[:120], "provider": "youtube", "tracks": [], "total": 0}))
  raise SystemExit(0)

tracks = []
for line in (p.stdout or "").splitlines():
  line = line.strip()
  if not line:
    continue
  try:
    raw = json.loads(line)
  except Exception:
    continue
  vid = str(raw.get("id") or "")
  title = str(raw.get("title") or "")
  url = str(raw.get("webpage_url") or raw.get("url") or "")
  if not url and vid:
    url = f"https://www.youtube.com/watch?v={vid}"
  if not title and not url:
    continue
  # Prefer playable videos; skip bare channel/playlist hits.
  if "/channel/" in url or "/@" in url or "/playlist" in url:
    continue
  if not vid and "watch?v=" not in url and "youtu.be/" not in url:
    continue
  artist = str(raw.get("uploader") or raw.get("channel") or "")
  art = ""
  thumbs = raw.get("thumbnails") or []
  if isinstance(thumbs, list) and thumbs:
    art = str((thumbs[-1] or {}).get("url") or "")
  if not art and vid:
    art = f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg"
  duration = raw.get("duration")
  tracks.append({
    "title": title,
    "artist": artist,
    "album": "",
    "path": url,
    "artUrl": art,
    "stream": True,
    "feed": False,
    "kind": "youtube",
    "albumId": "",
    "provider": "youtube",
    "providerLabel": "YouTube",
    "detail": " · ".join([x for x in ["YouTube", artist] if x]),
    "duration": duration,
    "track": {
      "title": title,
      "artist": artist,
      "path": url,
      "album_art_url": art,
      "stream": True,
      "provider_meta": {"kind": "youtube", "youtube.id": vid},
    },
  })

print(json.dumps({
  "ok": True,
  "provider": "youtube",
  "total": len(tracks),
  "tracks": tracks,
  "hitProviders": ["youtube"] if tracks else [],
}))
PY
