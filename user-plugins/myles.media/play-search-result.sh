#!/usr/bin/env bash
set -euo pipefail
# Argv JSON hit (preferred) or stdin JSON from search results.
# All sources play in-drawer via cliamp — never launch external apps.
if [[ $# -ge 1 && -n ${1:-} ]]; then
  raw="$1"
else
  raw="$(cat)"
fi
python3 - <<'PY' "$raw"
import json, sys, subprocess, re, shutil

hit = json.loads(sys.argv[1])
prov = str(hit.get("provider") or "")
track = hit.get("track") or {}
if not isinstance(track, dict):
  track = {}
if not track and (hit.get("path") or hit.get("title")):
  track = {
    "title": hit.get("title") or "",
    "artist": hit.get("artist") or "",
    "album": hit.get("album") or "",
    "path": hit.get("path") or "",
    "album_art_url": hit.get("artUrl") or "",
    "stream": bool(hit.get("stream")),
    "feed": bool(hit.get("feed")),
    "provider_meta": {
      "kind": hit.get("kind") or "",
      "albumID": hit.get("albumId") or "",
    },
  }
kind = str(hit.get("kind") or (track.get("provider_meta") or {}).get("kind") or "")
album_id = str(hit.get("albumId") or (track.get("provider_meta") or {}).get("albumID") or "")
path = str(hit.get("path") or track.get("path") or "")
title = str(hit.get("title") or track.get("title") or "")
artist = str(hit.get("artist") or track.get("artist") or "")
queue_only = bool(hit.get("queueOnly") or hit.get("playNext"))


def call(op, params, timeout=90, wait=True):
  cmd = ["cliamp", "remote", "call", op, "--params", json.dumps(params)]
  if wait:
    cmd.append("--wait")
  try:
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
  except Exception as e:
    return {"ok": False, "error": str(e)[:200], "job": {"state": "failed"}}
  try:
    data = json.loads(p.stdout or "{}")
  except Exception:
    data = {}
  if not data and (p.stderr or p.returncode):
    return {"ok": False, "error": (p.stderr or p.stdout or "failed")[:300], "job": {"state": "failed"}}
  if p.returncode != 0 and not data.get("job"):
    return {"ok": False, "error": (p.stderr or p.stdout or "failed")[:300], "job": {"state": "failed"}}
  return data


def job_ok(d):
  job = d.get("job") or {}
  state = str(job.get("state") or "")
  if state in ("succeeded", "queued", "running", "pending"):
    return True
  res = job.get("result")
  if isinstance(res, dict) and res.get("ok") is True:
    return True
  if d.get("ok") is True and job:
    return True
  return False


def job_err(d):
  job = d.get("job") or {}
  return str(d.get("error") or job.get("error") or (job.get("result") or {}).get("error") or "")[:240]


def play_url(url, provider, label, mode, wait_load=True):
  """Load into cliamp once and ensure transport is playing. No mid-play reload."""
  if queue_only:
    d = call("queue", {"path": url}, wait=True, timeout=60)
    ok = job_ok(d) or d.get("ok") is True
    print(json.dumps({
      "ok": ok,
      "mode": mode + "+queue",
      "provider": provider,
      "title": label or url,
      "path": url,
      "error": "" if ok else job_err(d),
    }))
    raise SystemExit(0 if ok else 2)

  d = call("url.load", {"path": url, "play": True}, wait=wait_load, timeout=90)
  ok = job_ok(d) or d.get("ok") is True
  if ok:
    call("play", {}, wait=False)
  snap = (d.get("job") or {}).get("snapshot") or {}
  resolved = ((snap.get("track") or {}).get("title") or "")
  out_title = label or resolved or url
  print(json.dumps({
    "ok": ok,
    "mode": mode,
    "provider": provider,
    "title": out_title,
    "path": url,
    "error": "" if ok else job_err(d),
  }))
  raise SystemExit(0 if ok else 2)


def is_youtube_watch(url):
  u = str(url or "")
  return ("youtube.com/" in u or "youtu.be/" in u) and "googlevideo.com" not in u


def normalize_youtube_url(url):
  u = str(url or "").strip()
  if not u:
    return ""
  m = re.search(r"(?:v=|youtu\.be/)([A-Za-z0-9_-]{6,})", u)
  if m:
    return "https://www.youtube.com/watch?v=" + m.group(1)
  return u


def youtube_video_id(url):
  m = re.search(r"(?:v=|youtu\.be/)([A-Za-z0-9_-]{6,})", str(url or ""))
  return m.group(1) if m else ""


def extract_youtube_audio(url):
  """Prefer durable audio-only (140/251). Avoid muxed itag 18."""
  if not shutil.which("yt-dlp"):
    return ""
  fmt = "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio[ext=webm]/bestaudio[acodec^=opus]/bestaudio/best[height<=?360]"
  cmd = [
    "yt-dlp", "-f", fmt, "-g", "--no-warnings",
    "--extractor-args", "youtube:player_client=web,android,ios",
    url,
  ]
  try:
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
  except Exception:
    return ""
  for line in (p.stdout or "").splitlines():
    line = line.strip()
    if line.startswith("http"):
      return line
  return ""


def play_youtube(url, label):
  watch = normalize_youtube_url(url) if is_youtube_watch(url) else url
  err = ""

  # 1) yt-dlp audio-only stream first — durable vs age-gate / bot checks.
  #    Prefer this over cliamp's native watch resolve, which can hang.
  stream = extract_youtube_audio(watch if is_youtube_watch(watch) else url)
  if stream:
    if queue_only:
      d = call("queue", {"path": stream}, wait=True, timeout=30)
      ok = job_ok(d) or d.get("ok") is True
      print(json.dumps({
        "ok": ok, "mode": "youtube-ytdlp-audio+queue", "provider": "youtube",
        "title": label or title or watch, "path": watch or url,
        "error": "" if ok else job_err(d),
      }))
      raise SystemExit(0 if ok else 2)
    d = call("url.load", {"path": stream, "play": True}, wait=True, timeout=45)
    if job_ok(d) or d.get("ok") is True:
      call("play", {}, wait=False)
      print(json.dumps({
        "ok": True, "mode": "youtube-ytdlp-audio", "provider": "youtube",
        "title": label or title or watch, "path": watch or url, "error": "",
      }))
      raise SystemExit(0)
    err = job_err(d) or err

  # 2) Native watch URL — short timeout so we fail fast into ytsearch.
  if is_youtube_watch(watch):
    d = call("url.load", {"path": watch, "play": True}, wait=True, timeout=12)
    if job_ok(d) or d.get("ok") is True:
      call("play", {}, wait=False)
      print(json.dumps({
        "ok": True, "mode": "youtube", "provider": "youtube",
        "title": label or watch, "path": watch, "error": "",
      }))
      raise SystemExit(0)
    err = job_err(d) or err
  else:
    err = err or "not-watch-url"

  # 3) ytsearch1 by title — last resort when resolve is blocked.
  hint = " ".join(x for x in [artist, title] if x).strip() or title or label
  if hint:
    q = hint if "official" in hint.lower() else (hint + " official audio")
    play_url("ytsearch1:" + q, "youtube", label or hint, "youtube-ytsearch", wait_load=True)

  print(json.dumps({
    "ok": False, "mode": "youtube", "provider": "youtube",
    "title": label or url, "path": url, "error": err or "youtube-failed",
  }))
  raise SystemExit(2)


def spotify_configured():
  d = call("provider.list", {}, timeout=8)
  res = (d.get("job") or {}).get("result") or {}
  for p in res.get("providers") or []:
    if isinstance(p, dict) and str(p.get("key") or "").lower() == "spotify":
      return True
  return False


# --- Spotify ---------------------------------------------------------------
if kind in ("spotify-track", "spotify") or prov == "spotify":
  label = " — ".join([x for x in [artist, title] if x]) or title or "Spotify"
  # Prefer real Spotify provider when configured in cliamp.
  if spotify_configured() and track:
    d = call("track.play", {"track": track}, wait=False)
    if job_ok(d) or d.get("ok") is True:
      call("play", {}, wait=False)
      print(json.dumps({"ok": True, "mode": "spotify-provider", "provider": "spotify", "title": label}))
      raise SystemExit(0)
    # Search Spotify catalog
    hint = str(hit.get("searchHint") or "").strip() or " ".join([artist, title]).strip()
    if hint:
      raw = call("provider.search", {"provider": "spotify", "query": hint, "limit": 5, "offset": 0}, timeout=20)
      res = (raw.get("job") or {}).get("result") or {}
      tracks = res.get("tracks") or res.get("results") or []
      if tracks and isinstance(tracks[0], dict):
        d = call("track.play", {"track": tracks[0]}, wait=False)
        if job_ok(d) or d.get("ok") is True:
          call("play", {}, wait=False)
          print(json.dumps({"ok": True, "mode": "spotify-search", "provider": "spotify", "title": label}))
          raise SystemExit(0)
  # Fallback: YouTube audio via ytsearch (in-drawer).
  hint = str(hit.get("searchHint") or "").strip()
  if not hint:
    hint = " ".join([artist, title]).strip()
  if not hint:
    print(json.dumps({"ok": False, "error": "missing-spotify-query", "mode": "spotify-drawer"}))
    raise SystemExit(2)
  query = hint if "official" in hint.lower() else (hint + " official audio")
  play_url("ytsearch1:" + query, "spotify", label, "spotify-ytsearch", wait_load=True)


# --- Radio Garden ----------------------------------------------------------
if kind == "radio-garden" or prov == "radio-garden":
  if not path:
    print(json.dumps({"ok": False, "error": "missing-radio-garden-url"}))
    raise SystemExit(2)
  play_url(path, "radio-garden", title or path, "radio-garden-stream", wait_load=False)


# --- YouTube ---------------------------------------------------------------
if kind == "youtube" or prov == "youtube" or is_youtube_watch(path):
  if not path and title:
    play_url("ytsearch1:" + title, "youtube", title, "youtube-ytsearch", wait_load=True)
  if not path:
    print(json.dumps({"ok": False, "error": "missing-youtube-url"}))
    raise SystemExit(2)
  play_youtube(path, title or path)


# --- Podcast / album feeds -------------------------------------------------
if (kind == "album" or hit.get("feed") or track.get("feed")) and (album_id or path) and prov:
  album = album_id or path
  if str(album).startswith("http://") or str(album).startswith("https://"):
    play_url(album, prov, title or album, "feed-url", wait_load=False)
  d = call("provider.load_album", {"provider": prov, "album": album}, wait=False)
  ok = job_ok(d) or d.get("ok") is True
  if ok:
    call("play", {}, wait=False)
  print(json.dumps({
    "ok": ok,
    "mode": "album",
    "provider": prov,
    "title": title or album,
    "error": "" if ok else job_err(d),
  }))
  raise SystemExit(0 if ok else 2)


# --- Direct HTTP(S) --------------------------------------------------------
if path.startswith("http://") or path.startswith("https://"):
  if is_youtube_watch(path):
    play_youtube(path, title or path)
  play_url(path, prov, title or path, "url.load", wait_load=False)


# --- Provider track object (local files, podcasts, …) ----------------------
if track and not queue_only:
  d = call("track.play", {"track": track}, wait=False)
  if job_ok(d) or d.get("ok") is True:
    call("play", {}, wait=False)
    print(json.dumps({"ok": True, "mode": "track.play", "provider": prov, "title": title}))
    raise SystemExit(0)
elif track and queue_only:
  d = call("track.queue", {"track": track}, wait=False)
  if job_ok(d) or d.get("ok") is True:
    print(json.dumps({"ok": True, "mode": "track.queue", "provider": prov, "title": title}))
    raise SystemExit(0)


# --- Path fallback ---------------------------------------------------------
if path:
  play_url(path, prov, title or path, "url.load", wait_load=False)

print(json.dumps({"ok": False, "error": "unplayable"}))
raise SystemExit(2)
PY
