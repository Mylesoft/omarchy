#!/usr/bin/env bash
# In-drawer search for Spotify / Radio Garden — never launches or focuses apps.
# Usage: search-drawer.sh <spotify|radio-garden> <query> [limit]
set -euo pipefail

hub="${1:-}"
query="${2:-}"
limit="${3:-10}"
query="$(printf '%s' "$query" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
[[ -n $query ]] || query="__popular__"

if [[ -z $hub ]]; then
  printf '%s\n' '{"ok":false,"error":"missing hub or query","tracks":[]}'
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PLUGIN_DIR="$SCRIPT_DIR"
export DRAWER_HUB="$hub"
export DRAWER_QUERY="$query"
export DRAWER_LIMIT="$limit"

python3 <<'PY'
import json, os, re, sys, subprocess, urllib.parse, urllib.request, urllib.error
sys.path.insert(0, os.environ.get("PLUGIN_DIR", os.path.expanduser("~/.config/omarchy/plugins/myles.media")))
from radio_freq import extract_radio_frequency

hub = os.environ["DRAWER_HUB"].strip().lower()
query = os.environ["DRAWER_QUERY"].strip()
limit = max(1, min(20, int(os.environ.get("DRAWER_LIMIT") or "10")))

UA_WEB = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
)
UA_MB = "myles.media/1.0 (omarchy drawer search)"


def http_json(url, headers=None, timeout=20):
    h = {"User-Agent": UA_WEB, "Accept": "application/json"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, headers=h)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def fail(err):
    print(json.dumps({
        "ok": False,
        "provider": hub,
        "mode": "drawer",
        "total": 0,
        "tracks": [],
        "error": err,
        "query": query,
    }))


def search_radio_garden():
    url = "https://radio.garden/api/search?q=" + urllib.parse.quote(query)
    data = http_json(url, {
        "Referer": "https://radio.garden/",
        "Origin": "https://radio.garden/",
    })
    hits = (data.get("hits") or {}).get("hits") or []
    tracks = []
    for h in hits:
        if not isinstance(h, dict):
            continue
        src = h.get("_source") or {}
        page = src.get("page") if isinstance(src.get("page"), dict) else src
        if not isinstance(page, dict):
            continue
        typ = str(page.get("type") or src.get("type") or "")
        path = str(page.get("url") or src.get("url") or "")
        title = str(page.get("title") or src.get("title") or "").strip()
        if not title or "/listen/" not in path:
            continue
        if typ and typ != "channel":
            continue
        channel_id = path.rstrip("/").split("/")[-1]
        if not channel_id:
            continue
        subtitle = str(page.get("subtitle") or src.get("subtitle") or "").strip()
        place = ""
        if isinstance(page.get("place"), dict):
            place = str(page["place"].get("title") or "")
        country = ""
        if isinstance(page.get("country"), dict):
            country = str(page["country"].get("title") or "")
        artist = subtitle or ", ".join([x for x in [place, country] if x])
        listen = f"https://radio.garden/api/ara/content/listen/{channel_id}/channel.mp3"
        freq = extract_radio_frequency(title)
        tracks.append({
            "title": title,
            "artist": artist,
            "album": country or "Radio Garden",
            "path": listen,
            "artUrl": "",
            "stream": True,
            "feed": False,
            "kind": "radio-garden",
            "albumId": channel_id,
            "provider": "radio-garden",
            "providerLabel": "Radio Garden",
            "detail": " · ".join([x for x in ["Radio Garden", artist] if x]),
            "channelId": channel_id,
            "gardenUrl": "https://radio.garden" + path,
            "frequency": freq,
        })
        if len(tracks) >= limit:
            break
    return tracks


def search_spotify():
    """
    Prefer cliamp provider.search when Spotify is configured; else Deezer→ISRC.
    Results play in the installed Spotify app via MPRIS OpenUri.
    """
    # Try real Spotify provider via cliamp when available.
    try:
        r = subprocess.run(
            ["cliamp", "remote", "call", "provider.search",
             "--params", json.dumps({"provider": "spotify", "query": query, "limit": limit}),
             "--wait"],
            capture_output=True, text=True, timeout=25,
        )
        data = json.loads(r.stdout or "{}")
        job = data.get("job") or {}
        res = job.get("result") if isinstance(job.get("result"), dict) else {}
        raw = res.get("tracks") or res.get("items") or res.get("results") or []
        if job.get("state") == "succeeded" and isinstance(raw, list) and raw:
            tracks = []
            for item in raw:
                if not isinstance(item, dict):
                    continue
                title = str(item.get("title") or item.get("name") or "").strip()
                if not title:
                    continue
                artist = str(item.get("artist") or "")
                if isinstance(item.get("artists"), list) and item["artists"]:
                    a0 = item["artists"][0]
                    artist = str(a0.get("name") if isinstance(a0, dict) else a0)
                album = str(item.get("album") or "")
                if isinstance(item.get("album"), dict):
                    album = str(item["album"].get("name") or item["album"].get("title") or "")
                path = str(item.get("uri") or item.get("path") or item.get("id") or "")
                if path and not path.startswith("spotify:") and len(path) < 40:
                    path = "spotify:track:" + path
                tracks.append({
                    "title": title,
                    "artist": artist,
                    "album": album,
                    "path": path,
                    "artUrl": str(item.get("artUrl") or item.get("artwork") or ""),
                    "stream": False,
                    "feed": False,
                    "kind": "spotify-track",
                    "provider": "spotify",
                    "providerLabel": "Spotify",
                    "detail": " · ".join([x for x in ["Spotify", artist, album] if x]),
                    "searchHint": f"{artist} {title}".strip(),
                    "via": "cliamp-provider",
                })
                if len(tracks) >= limit:
                    break
            if tracks:
                return tracks
    except Exception:
        pass

    import concurrent.futures
    url = (
        "https://api.deezer.com/search?q="
        + urllib.parse.quote(query)
        + f"&limit={limit}"
    )
    data = http_json(url, {"User-Agent": UA_MB})
    tracks = []
    for item in data.get("data") or []:
        if not isinstance(item, dict):
            continue
        title = str(item.get("title") or item.get("title_short") or "").strip()
        if not title:
            continue
        artist = ""
        if isinstance(item.get("artist"), dict):
            artist = str(item["artist"].get("name") or "")
        album = ""
        if isinstance(item.get("album"), dict):
            album = str(item["album"].get("title") or "")
        art = ""
        if isinstance(item.get("album"), dict):
            art = str(item["album"].get("cover_medium") or item["album"].get("cover") or "")
        isrc = str(item.get("isrc") or "").strip()
        deezer_id = str(item.get("id") or "")
        tracks.append({
            "title": title,
            "artist": artist,
            "album": album,
            "path": "",  # filled below when ISRC resolves
            "artUrl": art,
            "stream": False,
            "feed": False,
            "kind": "spotify-track",
            "albumId": deezer_id,
            "provider": "spotify",
            "providerLabel": "Spotify",
            "detail": " · ".join([x for x in ["Spotify", artist, album] if x]),
            "isrc": isrc,
            "deezerId": deezer_id,
            "searchHint": f"{artist} {title}".strip(),
        })
        if len(tracks) >= limit:
            break

    # Prefetch spotify:track URIs so click → OpenUri with no MusicBrainz wait.
    cache_dir = os.path.expanduser("~/.cache/myles.media")
    cache_path = os.path.join(cache_dir, "spotify-isrc.json")
    try:
        with open(cache_path, "r", encoding="utf-8") as f:
            cache = json.load(f)
        if not isinstance(cache, dict):
            cache = {}
    except Exception:
        cache = {}

    def resolve_one(t):
        isrc = str(t.get("isrc") or "").strip().upper()
        if not isrc:
            return t
        cached = str(cache.get(isrc) or "")
        if cached.startswith("spotify:track:"):
            t["path"] = cached
            return t
        try:
            det = http_json(
                "https://musicbrainz.org/ws/2/isrc/"
                + urllib.parse.quote(isrc)
                + "?inc=url-rels&fmt=json",
                {"User-Agent": UA_MB, "Accept": "application/json"},
                timeout=8,
            )
            for rec in det.get("recordings") or []:
                for rel in rec.get("relations") or []:
                    u = ((rel.get("url") or {}).get("resource") or "")
                    m = re.search(r"open\.spotify\.com/track/([A-Za-z0-9]+)", u)
                    if m:
                        uri = "spotify:track:" + m.group(1)
                        t["path"] = uri
                        cache[isrc] = uri
                        return t
        except Exception:
            pass
        return t

    # Cap concurrency — MusicBrainz soft-limits around 1–2 req/s.
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
        tracks = list(ex.map(resolve_one, tracks))
    try:
        os.makedirs(cache_dir, exist_ok=True)
        tmp = cache_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(cache, f)
        os.replace(tmp, cache_path)
    except Exception:
        pass
    return tracks


def search_radio_nearby_or_popular():
    """Popular / 'near me' station picks via Radio Garden search seeds."""
    seeds = []
    q = query.strip().lower()
    if q in ("__nearby__", "nearby", "near me", "near-me"):
        try:
            geo = http_json("https://ipapi.co/json/", {"User-Agent": UA_MB}, timeout=6)
            country = str(geo.get("country_name") or geo.get("country") or "")
            city = str(geo.get("city") or "")
            if city:
                seeds.append(city)
            if country:
                seeds.append(country)
        except Exception:
            pass
        if not seeds:
            seeds = ["Nairobi", "London", "New York", "Tokyo"]
    else:
        seeds = ["popular", "hits", "top"]
    seen = set()
    tracks = []
    saved = query
    try:
        for seed in seeds:
            # Mutate module-level query for reuse of search_radio_garden().
            globals()["query"] = seed
            for t in search_radio_garden():
                key = t.get("channelId") or t.get("path")
                if key in seen:
                    continue
                seen.add(key)
                t = dict(t)
                t["detail"] = ("Nearby · " if q.startswith("__nearby") or "near" in q else "Popular · ") + str(t.get("detail") or "")
                tracks.append(t)
                if len(tracks) >= limit:
                    return tracks
    finally:
        globals()["query"] = saved
    return tracks


try:
    if hub in ("radio-garden", "radio-garden-app", "radio"):
        provider = "radio-garden"
        qlow = query.strip().lower()
        if qlow in ("__nearby__", "nearby", "near me", "near-me", "__popular__", "popular"):
            tracks = search_radio_nearby_or_popular()
        else:
            tracks = search_radio_garden()
    elif hub in ("spotify", "spotify-app"):
        provider = "spotify"
        tracks = search_spotify()
    else:
        fail(f"unsupported hub: {hub}")
        raise SystemExit(0)
except Exception as e:
    fail(str(e)[:160])
    raise SystemExit(0)

print(json.dumps({
    "ok": True,
    "provider": provider,
    "mode": "drawer",
    "total": len(tracks),
    "tracks": tracks,
    "error": "" if tracks else "No results",
    "query": query,
}))
PY
