#!/usr/bin/env bash
# Search one provider, or all searchable providers in parallel.
# Usage: search-provider.sh <provider|all|csv> <query> [limit_per_provider]
set -euo pipefail
prov_arg="${1:-}"
query="${2:-}"
limit="${3:-8}"
[[ -n $prov_arg ]] || { echo '{"ok":false,"error":"missing-provider"}'; exit 1; }
[[ -n $query ]] || { echo '{"ok":true,"provider":"all","tracks":[],"total":0,"providers":[]}'; exit 0; }

export CLIAMP_SEARCH_QUERY="$query"
export CLIAMP_SEARCH_LIMIT="$limit"
export CLIAMP_SEARCH_PROV="$prov_arg"

python3 <<'PY'
import json, os, subprocess, concurrent.futures

query = os.environ["CLIAMP_SEARCH_QUERY"]
limit = int(os.environ["CLIAMP_SEARCH_LIMIT"])
prov_arg = os.environ["CLIAMP_SEARCH_PROV"].strip().lower()

LABELS = {
  "radio": "Radio",
  "podcast": "Podcasts",
  "local": "Local",
  "spotify": "Spotify",
  "ytmusic": "YouTube Music",
  "youtube": "YouTube",
  "yt": "YouTube",
  "navidrome": "Navidrome",
  "lyrion": "Lyrion",
  "plex": "Plex",
  "jellyfin": "Jellyfin",
  "emby": "Emby",
  "qobuz": "Qobuz",
  "tidal": "Tidal",
  "soundcloud": "SoundCloud",
  "mixcloud": "Mixcloud",
  "netease": "NetEase",
  "yandex": "Yandex Music",
  "audiobookshelf": "Audiobookshelf",
  "abs": "Audiobookshelf",
}

KNOWN = [
  "radio", "podcast", "local", "spotify", "ytmusic", "youtube",
  "navidrome", "lyrion", "plex", "jellyfin", "emby", "qobuz", "tidal",
  "soundcloud", "mixcloud", "netease", "yandex", "audiobookshelf",
]

def call(op, params, timeout=12):
  cmd = ["cliamp", "remote", "call", op, "--params", json.dumps(params), "--wait"]
  try:
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return json.loads(p.stdout or "{}")
  except subprocess.TimeoutExpired:
    return {"ok": False, "error": "Source timed out"}
  except FileNotFoundError:
    return {"ok": False, "error": "cliamp is not installed"}
  except Exception as e:
    return {"ok": False, "error": str(e)[:120] or "Source request failed"}

def configured_searchable():
  d = call("provider.list", {})
  r = (d.get("job") or {}).get("result") or d.get("result") or {}
  out = []
  for p in r.get("providers") or []:
    if not isinstance(p, dict):
      continue
    key = str(p.get("key") or p.get("id") or "").lower()
    if not key or p.get("searchable") is False:
      continue
    out.append(key)
  return out

def resolve_providers():
  if prov_arg in ("all", "*", "any"):
    conf = configured_searchable()
    seen = set()
    ordered = []
    for k in conf + KNOWN:
      if k in seen:
        continue
      seen.add(k)
      ordered.append(k)
    return ordered
  if "," in prov_arg:
    return [p.strip() for p in prov_arg.split(",") if p.strip()]
  return [prov_arg]

def normalize_tracks(prov, raw):
  j = raw.get("job") or {}
  r = j.get("result") or raw.get("result") or {}
  tracks = r.get("tracks") or r.get("playlists") or r.get("results") or []
  label = LABELS.get(prov, prov.title())
  out = []
  for t in tracks:
    if not isinstance(t, dict):
      continue
    title = str(t.get("title") or t.get("name") or "")
    path = str(t.get("path") or "")
    if not title and not path:
      continue
    meta = t.get("provider_meta") or {}
    artist = str(t.get("artist") or t.get("genre") or meta.get("radio.country") or "")
    album = str(t.get("album") or t.get("station") or "")
    out.append({
      "title": title,
      "artist": artist,
      "album": album,
      "path": path,
      "artUrl": str(t.get("album_art_url") or t.get("art") or t.get("artwork") or ""),
      "stream": bool(t.get("stream")),
      "feed": bool(t.get("feed")),
      "kind": str(meta.get("kind") or ("album" if t.get("feed") else "track")),
      "albumId": str(meta.get("albumID") or ""),
      "provider": prov,
      "providerLabel": label,
      "detail": " · ".join([x for x in [label, artist, album] if x]),
      "track": t,
    })
  ok = j.get("state") == "succeeded" or bool(r.get("ok", False))
  error = j.get("error") or raw.get("error") or r.get("error")
  if not ok and not error:
    error = "Provider returned no results"
  return out, ok and not error, error

def search_one(prov):
  raw = call("provider.search", {
    "provider": prov,
    "query": query,
    "limit": limit,
    "offset": 0,
  })
  tracks, ok, err = normalize_tracks(prov, raw)
  return {
    "provider": prov,
    "label": LABELS.get(prov, prov.title()),
    "ok": ok,
    "error": err,
    "count": len(tracks),
    "tracks": tracks,
  }

providers = resolve_providers()
results = []
with concurrent.futures.ThreadPoolExecutor(max_workers=min(12, max(1, len(providers)))) as ex:
  futs = {ex.submit(search_one, p): p for p in providers}
  for fut in concurrent.futures.as_completed(futs):
    try:
      results.append(fut.result())
    except Exception as e:
      results.append({
        "provider": futs[fut],
        "label": LABELS.get(futs[fut], futs[fut]),
        "ok": False,
        "error": str(e)[:120],
        "count": 0,
        "tracks": [],
      })

by_prov = {r["provider"]: r for r in results}

# Round-robin merge so Radio / Podcasts / Spotify share the list.
merged = []
idx = 0
cap = max(limit * 3, 24)
while len(merged) < cap:
  added = False
  for p in providers:
    tracks = by_prov.get(p, {}).get("tracks") or []
    if idx < len(tracks):
      merged.append(tracks[idx])
      added = True
      if len(merged) >= cap:
        break
  if not added:
    break
  idx += 1

hit_providers = [p for p in providers if (by_prov.get(p) or {}).get("count")]
print(json.dumps({
  "ok": True,
  "provider": "all" if prov_arg in ("all", "*", "any") or "," in prov_arg else prov_arg,
  "providers": providers,
  "hitProviders": hit_providers,
  "total": len(merged),
  "tracks": merged,
  "perProvider": [
    {
      "provider": p,
      "label": (by_prov.get(p) or {}).get("label") or LABELS.get(p, p),
      "count": (by_prov.get(p) or {}).get("count") or 0,
      "ok": bool((by_prov.get(p) or {}).get("ok")),
      "error": str((by_prov.get(p) or {}).get("error") or ""),
    }
    for p in providers
  ],
}))
PY
