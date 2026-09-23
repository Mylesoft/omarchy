#!/usr/bin/env bash
# Resolve Radio Garden channel metadata (title, place, frequency).
# Usage: resolve-radio-channel.sh <channelId|listen-url>
set -euo pipefail
raw="${1:-}"
[[ -n $raw ]] || { echo '{"ok":false,"error":"missing-id"}'; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PLUGIN_DIR="$SCRIPT_DIR"
export RG_RAW="$raw"
python3 <<'PY'
import json, os, re, sys, urllib.request
sys.path.insert(0, os.environ.get("PLUGIN_DIR", os.path.expanduser("~/.config/omarchy/plugins/myles.media")))
from radio_freq import extract_radio_frequency as extract_freq

raw = os.environ.get("RG_RAW", "").strip()
UA = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
)

def channel_id(s):
    m = re.search(r"/listen/([A-Za-z0-9_-]+)", s)
    if m:
        return m.group(1)
    if re.fullmatch(r"[A-Za-z0-9_-]{4,}", s):
        return s
    return ""

cid = channel_id(raw)
if not cid:
    print(json.dumps({"ok": False, "error": "bad-id"}))
    raise SystemExit(0)

url = f"https://radio.garden/api/ara/content/channel/{cid}"
try:
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "application/json",
        "Referer": "https://radio.garden/",
        "Origin": "https://radio.garden/",
    })
    with urllib.request.urlopen(req, timeout=12) as r:
        data = json.loads(r.read().decode("utf-8", "replace"))
except Exception as e:
    print(json.dumps({"ok": False, "error": str(e)[:120], "channelId": cid}))
    raise SystemExit(0)

page = data.get("data") if isinstance(data, dict) else None
if not isinstance(page, dict):
    print(json.dumps({"ok": False, "error": "no-data", "channelId": cid}))
    raise SystemExit(0)

title = str(page.get("title") or "").strip()
place = ""
if isinstance(page.get("place"), dict):
    place = str(page["place"].get("title") or "").strip()
country = ""
if isinstance(page.get("country"), dict):
    country = str(page["country"].get("title") or "").strip()
artist = ", ".join([x for x in [place, country] if x])
freq = extract_freq(title)
path = f"https://radio.garden/api/ara/content/listen/{cid}/channel.mp3"
garden = "https://radio.garden" + str(page.get("url") or f"/listen/{cid}")

print(json.dumps({
    "ok": True,
    "channelId": cid,
    "title": title,
    "artist": artist,
    "album": country or "Radio Garden",
    "place": place,
    "country": country,
    "frequency": freq,
    "path": path,
    "gardenUrl": garden,
    "website": str(page.get("website") or ""),
    "stream": True,
    "provider": "radio-garden",
    "providerLabel": "Radio Garden",
    "detail": " · ".join([x for x in ["Radio Garden", artist] if x]),
}))
PY
