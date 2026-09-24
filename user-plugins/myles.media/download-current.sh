#!/usr/bin/env bash
# Download the currently playing track to ~/Downloads/Media.
# Emits NDJSON progress lines, then a final {"event":"done",...} line.
# Usage:
#   download-current.sh '<json payload>'
#   download-current.sh --list
set -euo pipefail

if [[ ${1:-} == "--remove" ]]; then
  export REMOVE_PATH="${2:-}"
  python3 <<'PY'
import json, os
from pathlib import Path
reg_path = Path.home() / ".local/state/omarchy/media/downloads.json"
media_root = (Path.home() / "Downloads" / "Media").resolve()
target = os.environ.get("REMOVE_PATH") or ""
try:
  tp = Path(target).resolve()
  tp.relative_to(media_root)
except Exception:
  print(json.dumps({"ok": False, "error": "refuse-path"}))
  raise SystemExit(0)
try:
  data = json.loads(reg_path.read_text())
  items = data.get("items") if isinstance(data, dict) else []
  items = [it for it in (items or []) if isinstance(it, dict) and str(it.get("path") or "") != target]
  reg_path.write_text(json.dumps({"items": items[:200]}, indent=2))
  print(json.dumps({"ok": True, "removed": target}))
except Exception as e:
  print(json.dumps({"ok": False, "error": str(e)[:120]}))
PY
  exit 0
fi

if [[ ${1:-} == "--list" ]]; then
  python3 <<'PY'
import json, os, re
from pathlib import Path
from datetime import datetime, timezone

outdir = Path.home() / "Downloads" / "Media"
outdir.mkdir(parents=True, exist_ok=True)
reg_path = Path.home() / ".local/state/omarchy/media/downloads.json"

def load_reg():
  try:
    data = json.loads(reg_path.read_text())
    items = data.get("items") if isinstance(data, dict) else []
    return items if isinstance(items, list) else []
  except Exception:
    return []

# A shell restart or interrupted process can leave a registry row stuck at
# "downloading". Keep it active only while its recorded worker PID still runs.
def worker_is_running():
  try:
    pid = int((Path.home() / ".local/state/omarchy/media/download.pid").read_text().strip())
    os.kill(pid, 0)
    return True
  except (OSError, ValueError, FileNotFoundError):
    return False

reg_items = load_reg()
if not worker_is_running():
  changed = False
  for item in reg_items:
    if isinstance(item, dict) and item.get("status") == "downloading":
      item["status"] = "failed"
      item["error"] = "interrupted"
      changed = True
  if changed:
    reg_path.write_text(json.dumps({"items": reg_items[:200]}, indent=2))


def fmt_size(n):
  n = float(n or 0)
  for u in ("B", "KB", "MB", "GB"):
    if n < 1024 or u == "GB":
      return f"{n:.0f} {u}" if u == "B" else f"{n:.1f} {u}"
    n /= 1024

reg = {str(it.get("path") or ""): it for it in load_reg() if isinstance(it, dict) and it.get("path")}
items = []
seen = set()
for p in sorted(outdir.iterdir(), key=lambda x: x.stat().st_mtime, reverse=True):
  if not p.is_file():
    continue
  name = p.name.lower()
  if name.endswith((".part", ".ytdl", ".temp", ".webp", ".jpg", ".png", ".json")):
    continue
  if p.stat().st_size < 1024:
    continue
  meta = reg.get(str(p), {})
  title = str(meta.get("title") or "")
  artist = str(meta.get("artist") or "")
  if not title:
    stem = p.stem
    if " - " in stem:
      artist, title = stem.split(" - ", 1)
    else:
      title = stem
  mtime = datetime.fromtimestamp(p.stat().st_mtime, tz=timezone.utc).isoformat()
  items.append({
    "id": str(meta.get("id") or ("file:" + p.name)),
    "title": title,
    "artist": artist,
    "path": str(p),
    "provider": str(meta.get("provider") or ""),
    "sourcePath": str(meta.get("sourcePath") or ""),
    "searchHint": str(meta.get("searchHint") or ""),
    "stream": bool(meta.get("stream")),
    "status": "done",
    "pct": 100,
    "bytes": p.stat().st_size,
    "sizeLabel": fmt_size(p.stat().st_size),
    "addedAt": str(meta.get("addedAt") or mtime),
    "mode": str(meta.get("mode") or "file"),
    "error": "",
  })
  seen.add(str(p))

# Keep in-progress / failed entries that aren't files yet
for path, meta in reg.items():
  if path in seen:
    continue
  st = str(meta.get("status") or "")
  if st in ("downloading", "failed"):
    items.insert(0, {
      "id": str(meta.get("id") or path),
      "title": str(meta.get("title") or "Download"),
      "artist": str(meta.get("artist") or ""),
      "path": path,
      "provider": str(meta.get("provider") or ""),
      "sourcePath": str(meta.get("sourcePath") or ""),
      "searchHint": str(meta.get("searchHint") or ""),
      "stream": bool(meta.get("stream")),
      "status": st,
      "pct": int(meta.get("pct") or 0),
      "bytes": int(meta.get("bytes") or 0),
      "sizeLabel": str(meta.get("sizeLabel") or ""),
      "addedAt": str(meta.get("addedAt") or ""),
      "mode": str(meta.get("mode") or ""),
      "error": str(meta.get("error") or ""),
    })

print(json.dumps({"ok": True, "items": items, "dir": str(outdir)}))
PY
  exit 0
fi

raw="${1:-}"
[[ -n $raw ]] || { echo '{"event":"done","ok":false,"error":"missing-payload"}'; exit 1; }

export DOWNLOAD_PAYLOAD="$raw"
python3 <<'PY'
import json, os, re, shutil, subprocess, sys, time
from pathlib import Path
from datetime import datetime, timezone
from urllib.parse import urlparse

hit = json.loads(os.environ["DOWNLOAD_PAYLOAD"])
title = str(hit.get("title") or "track").strip() or "track"
artist = str(hit.get("artist") or "").strip()
path = str(hit.get("path") or "").strip()
provider = str(hit.get("provider") or "").strip().lower()
identity = str(hit.get("identity") or "").strip().lower()
search_hint = str(hit.get("searchHint") or "").strip()
record_requested = hit.get("recordSeconds") is not None or hit.get("recordMinutes") is not None
download_format = str(hit.get("downloadFormat") or "mp3").lower()
if download_format not in ("mp3", "video"):
  download_format = "mp3"

outdir = Path.home() / "Downloads" / "Media"
outdir.mkdir(parents=True, exist_ok=True)
state_dir = Path.home() / ".local/state/omarchy/media"
state_dir.mkdir(parents=True, exist_ok=True)
reg_path = state_dir / "downloads.json"


def emit(obj):
  sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
  sys.stdout.flush()


def progress(pct, status="", bytes_n=0):
  emit({
    "event": "progress",
    "pct": max(0, min(100, int(pct))),
    "status": status or "",
    "bytes": int(bytes_n or 0),
    "title": title,
  })


def safe_name(s, limit=80):
  s = re.sub(r"[\\/:*?\"<>|]+", "_", s)
  s = re.sub(r"\s+", " ", s).strip(" ._")
  return (s or "track")[:limit]


def load_reg():
  try:
    data = json.loads(reg_path.read_text())
    items = data.get("items") if isinstance(data, dict) else []
    return items if isinstance(items, list) else []
  except Exception:
    return []


def save_reg(items):
  reg_path.write_text(json.dumps({"items": items[:200]}, indent=2))


def upsert_reg(entry):
  items = load_reg()
  key = str(entry.get("id") or entry.get("path") or "")
  out = []
  replaced = False
  for it in items:
    if not isinstance(it, dict):
      continue
    ik = str(it.get("id") or it.get("path") or "")
    if key and ik == key:
      out.append(entry)
      replaced = True
    else:
      out.append(it)
  if not replaced:
    out.insert(0, entry)
  save_reg(out)


def fmt_size(n):
  n = float(n or 0)
  for u in ("B", "KB", "MB", "GB"):
    if n < 1024 or u == "GB":
      return f"{n:.0f} {u}" if u == "B" else f"{n:.1f} {u}"
    n /= 1024


def done(ok, mode, dest="", error=""):
  entry = {
    # Keep the pending record's stable ID so completion replaces it even when
    # yt-dlp chooses a different extension or an existing file is reused.
    "id": dl_id,
    "title": title,
    "artist": artist,
    "path": str(dest) if dest else "",
    "provider": provider,
    "sourcePath": path,
    "searchHint": search_hint,
    "stream": bool(hit.get("stream")),
    "status": "done" if ok else "failed",
    "pct": 100 if ok else int(getattr(done, "_pct", 0) or 0),
    "bytes": Path(dest).stat().st_size if dest and Path(dest).is_file() else 0,
    "sizeLabel": fmt_size(Path(dest).stat().st_size) if dest and Path(dest).is_file() else "",
    "addedAt": datetime.now(timezone.utc).isoformat(),
    "mode": mode,
    "format": download_format,
    "error": error or "",
  }
  if entry["path"] or error:
    upsert_reg(entry)
  try:
    (state_dir / "download.pid").unlink(missing_ok=True)
  except Exception:
    pass
  # Size warning for oversized saves
  warn = ""
  if ok and entry["bytes"] > 80 * 1024 * 1024:
    warn = f"Large file ({entry['sizeLabel']})"
  emit({
    "event": "done",
    "ok": ok,
    "mode": mode,
    "path": str(dest) if dest else "",
    "title": title,
    "artist": artist,
    "error": error or "",
    "warning": warn,
    "item": entry,
  })
  raise SystemExit(0 if ok else 2)


base = safe_name(f"{artist} - {title}" if artist else title)
if record_requested:
  # Each capture is a new file, even when this station/title was recorded before.
  capture_stamp = datetime.now().strftime("%Y-%m-%d %H-%M-%S")
  stem = outdir / f"{base} - Recording {capture_stamp}"
  dl_id = "record:" + capture_stamp + ":" + base[:40]
else:
  stem = outdir / base
  dl_id = "dl:" + download_format + ":" + base[:42]


def already_have():
  expected = (".mp3",) if download_format == "mp3" else (".mp4", ".mkv", ".webm", ".mov", ".m4v")
  for p in outdir.glob(base + ".*"):
    if not p.is_file():
      continue
    name = p.name.lower()
    if name.endswith((".part", ".ytdl", ".temp")):
      continue
    if p.suffix.lower() in expected and p.stat().st_size > 1024:
      return p
  return None


def is_youtube_watch(u):
  u = str(u or "")
  return ("youtube.com/" in u or "youtu.be/" in u) and "googlevideo.com" not in u


def normalize_youtube(u):
  m = re.search(r"(?:v=|youtu\.be/)([A-Za-z0-9_-]{6,})", str(u or ""))
  if m:
    return "https://www.youtube.com/watch?v=" + m.group(1)
  return str(u or "")


def is_googlevideo(u):
  return "googlevideo.com" in str(u or "").lower()


# Resolve a durable download target.
spotify_like = (
  path.startswith("spotify:")
  or "spotify" in identity
  or provider == "spotify"
)
url = path
mode = "url"

if is_googlevideo(url):
  # Expired CDN URLs fail — fall back to title search / hint.
  url = ""
if is_youtube_watch(url):
  url = normalize_youtube(url)
  mode = "youtube"
elif url.startswith("ytsearch"):
  mode = "ytsearch"
elif spotify_like or not url or url.startswith("spotify:"):
  q = search_hint or ((" ".join([artist, title]).strip()) if artist else title)
  if not q:
    progress(0, "Nothing to download")
    done(False, "spotify", error="nothing-to-download")
  if "official" not in q.lower():
    q = q + " official audio"
  url = f"ytsearch1:{q}"
  mode = "ytsearch"

existing = already_have()
if existing:
  progress(100, "Already downloaded")
  done(True, "exists", existing)

# Dedupe by normalized title+artist, but never substitute audio for video or
# video for audio. Older registry rows may not have a format field, so also
# verify the actual filename extension.
video_extensions = {".mp4", ".mkv", ".webm", ".mov", ".m4v"}
def path_matches_requested_format(candidate):
  suffix = Path(str(candidate)).suffix.lower()
  return suffix == ".mp3" if download_format == "mp3" else suffix in video_extensions

norm = f"{artist} {title}".strip().lower()
for it in load_reg():
  if not isinstance(it, dict):
    continue
  other = f"{it.get('artist','')} {it.get('title','')}".strip().lower()
  candidate = Path(str(it.get("path") or ""))
  recorded_format = str(it.get("format") or "").lower()
  if (norm and other == norm and it.get("status") == "done"
      and candidate.is_file() and path_matches_requested_format(candidate)
      and recorded_format in ("", download_format)):
    progress(100, "Already in library")
    done(True, "dedupe-reg", candidate)

# PID file so the panel can cancel (process group — never pkill -f yt-dlp).
try:
  os.setpgrp()
except Exception:
  pass
pid_path = state_dir / "download.pid"
pid_path.write_text(str(os.getpid()))

upsert_reg({
  "id": dl_id,
  "title": title,
  "artist": artist,
  "path": str(stem) + (".mp3" if download_format == "mp3" else ".mp4"),
  "provider": provider,
  "sourcePath": path,
  "searchHint": search_hint,
  "stream": bool(hit.get("stream")),
  "status": "downloading",
  "pct": 0,
  "bytes": 0,
  "sizeLabel": "",
  "addedAt": datetime.now(timezone.utc).isoformat(),
  "mode": mode,
  "format": download_format,
  "error": "",
})
progress(1, "Starting…")
# Local file → copy video, or extract the requested MP3 audio.
if path.startswith("/") and Path(path).is_file():
  source = Path(path)
  if download_format == "video":
    dest = stem.with_suffix(source.suffix or ".mp4")
    progress(10, "Copying video…")
    shutil.copy2(source, dest)
    progress(100, "Done")
    done(True, "copy-video", dest)
  ffmpeg = shutil.which("ffmpeg")
  if not ffmpeg:
    done(False, "local-audio", error="ffmpeg-not-installed")
  dest = stem.with_suffix(".mp3")
  p = subprocess.run([ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", str(source), "-vn", "-c:a", "libmp3lame", "-q:a", "3", str(dest)], capture_output=True, text=True)
  if p.returncode == 0 and dest.exists() and dest.stat().st_size > 1024:
    done(True, "local-audio", dest)
  dest.unlink(missing_ok=True)
  done(False, "local-audio", error=(p.stderr or "audio-extract-failed")[-220:])

# Local file → copy
# Live radio vs finite episode/track files.
looks_finite = bool(re.search(r"\.(mp3|aac|ogg|flac|m4a|wav)(\?|$)", url, re.I))
looks_video_file = bool(re.search(r"\.(mp4|m4v|mov|mkv|webm|avi)(\?|$)", url, re.I))
live_hint = any(
  x in url.lower()
  for x in ("/stream", "icecast", "streamguys", "cdnstream", ".m3u8", "radio.garden")
)
# Never treat YouTube / ytsearch as a live radio capture.
is_live = (
  mode == "url"
  and bool(url)
  and (record_requested or bool(hit.get("stream")) or live_hint)
  and (record_requested or not looks_finite)
  and not is_youtube_watch(url)
  and "youtube" not in url.lower()
  and "youtu.be" not in url.lower()
  and not url.startswith("ytsearch")
)

if mode == "url" and url.startswith("http") and is_live:
  dest = stem.with_suffix(".mp3")
  partial = Path(str(dest) + ".part")
  partial.unlink(missing_ok=True)
  # Configurable capture window (default 45s, max 10 min).
  record_secs = 45
  try:
    if hit.get("recordSeconds") is not None:
      record_secs = int(float(hit.get("recordSeconds")))
    elif hit.get("recordMinutes") is not None:
      record_secs = int(float(hit.get("recordMinutes")) * 60)
  except Exception:
    record_secs = 45
  record_secs = max(15, min(600, record_secs))
  progress(5, f"Recording stream · {record_secs}s…")
  ffmpeg = shutil.which("ffmpeg")
  if not ffmpeg:
    done(False, "stream-record", error="ffmpeg-not-installed")
  cmd = [ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
         "-rw_timeout", "15000000"]
  if "radio.garden" in url.lower():
    cmd += ["-headers", "Referer: https://radio.garden/\r\nOrigin: https://radio.garden\r\n"]
  cmd += ["-i", url, "-t", str(record_secs), "-map", "0:a:0", "-vn",
          "-c:a", "libmp3lame", "-q:a", "3", "-metadata", f"title={title}"]
  if artist:
    cmd += ["-metadata", f"artist={artist}"]
  cmd += [str(partial)]
  try:
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=record_secs + 30)
  except subprocess.TimeoutExpired as e:
    p = e
  if (getattr(p, "returncode", -1) == 0 and partial.exists()
      and partial.stat().st_size > 8_000):
    partial.replace(dest)
    progress(100, "Done")
    done(True, "stream-record", dest)
  partial.unlink(missing_ok=True)
  stderr = getattr(p, "stderr", "") or ""
  if isinstance(stderr, bytes):
    stderr = stderr.decode("utf-8", "replace")
  done(False, "stream-record", error=(stderr.strip() or "stream-capture-failed")[:220])

if mode == "url" and url.startswith("http") and download_format == "video" and looks_video_file:
  extm = re.search(r"\.(mp4|m4v|mov|mkv|webm|avi)(\?|$)", url, re.I)
  ext = "." + extm.group(1).lower() if extm else ".mp4"
  dest = stem.with_suffix(ext)
  partial = Path(str(dest) + ".part")
  partial.unlink(missing_ok=True)
  progress(5, "Downloading video…")
  p = subprocess.run(["curl", "-fL", "--max-time", "1800", "-A", "Mozilla/5.0", "-o", str(partial), url], capture_output=True, text=True)
  if p.returncode == 0 and partial.exists() and partial.stat().st_size > 8000:
    partial.replace(dest)
    done(True, "http-video", dest)
  partial.unlink(missing_ok=True)
  done(False, "http-video", error=(p.stderr or "http-video-download-failed")[-220:])

if mode == "url" and url.startswith("http") and looks_finite and "youtube" not in url.lower():
  if download_format == "mp3" and not url.lower().split("?",1)[0].endswith(".mp3"):
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
      done(False, "http-audio", error="ffmpeg-not-installed")
    rawdest = stem.with_suffix(".source")
    rawpart = Path(str(rawdest) + ".part")
    p = subprocess.run(["curl", "-fL", "--max-time", "600", "-A", "Mozilla/5.0", "-o", str(rawpart), url], capture_output=True, text=True)
    if p.returncode != 0 or not rawpart.exists() or rawpart.stat().st_size <= 1024:
      rawpart.unlink(missing_ok=True)
      done(False, "http-audio", error=(p.stderr or "http-download-failed")[-220:])
    p = subprocess.run([ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", str(rawpart), "-vn", "-c:a", "libmp3lame", "-q:a", "3", str(stem.with_suffix(".mp3"))], capture_output=True, text=True)
    rawpart.unlink(missing_ok=True)
    if p.returncode == 0 and stem.with_suffix(".mp3").exists(): done(True, "http-audio", stem.with_suffix(".mp3"))
    done(False, "http-audio", error=(p.stderr or "audio-convert-failed")[-220:])
  ext = ".mp3"
  m = re.search(r"\.(mp3|aac|ogg|flac|m4a|wav)(\?|$)", url, re.I)
  if m:
    ext = "." + m.group(1).lower()
  dest = stem.with_suffix(ext)
  partial = Path(str(dest) + ".part")
  partial.unlink(missing_ok=True)
  progress(5, "Downloading file…")
  # curl with progress meter on stderr as #/#
  proc = subprocess.Popen([
    "curl", "-fL", "--max-time", "600", "-A", "Mozilla/5.0",
    "--progress-bar", "-o", str(partial), url,
  ], stderr=subprocess.PIPE, stdout=subprocess.DEVNULL, text=True)
  last_pct = 5
  buf = ""
  while True:
    chunk = proc.stderr.read(64) if proc.stderr else ""
    if not chunk:
      if proc.poll() is not None:
        break
      time.sleep(0.05)
      continue
    buf += chunk
    # progress-bar uses carriage returns; grab trailing percent-like numbers
    for part in re.split(r"[\r\n]+", buf):
      mm = re.search(r"(\d{1,3}(?:\.\d+)?)\%", part)
      if mm:
        pct = int(float(mm.group(1)))
        if pct >= last_pct:
          last_pct = pct
          progress(pct, "Downloading…", partial.stat().st_size if partial.exists() else 0)
    if "\r" in buf:
      buf = buf.split("\r")[-1]
  rc = proc.wait()
  if rc == 0 and partial.exists() and partial.stat().st_size > 8_000:
    partial.replace(dest)
    progress(100, "Done")
    done(True, "http-file", dest)
  partial.unlink(missing_ok=True)
  done(False, "http-file", error="http-download-failed")

if not shutil.which("yt-dlp"):
  done(False, mode, error="yt-dlp-missing")

outtmpl = str(stem) + ".%(ext)s"
if download_format == "video":
  progress(2, "Video + audio download…")
  cmd = ["yt-dlp", "-f", "bestvideo[height<=1080]+bestaudio/best[height<=1080]/best", "--merge-output-format", "mp4", "--extractor-args", "youtube:player_client=web,android,ios", "--no-playlist", "--newline", "-o", outtmpl, "--no-warnings", url]
else:
  progress(2, "Audio-only convert (mp3)…")
  cmd = ["yt-dlp", "-f", "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio[ext=webm]/bestaudio/best", "-x", "--audio-format", "mp3", "--audio-quality", "0", "--extractor-args", "youtube:player_client=web,android,ios", "--no-playlist", "--newline", "-o", outtmpl, "--no-warnings", "--no-keep-video", url]
progress(3, "Fetching…")
proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
last_pct = 3
err_tail = []
for line in proc.stdout or []:
  line = (line or "").rstrip()
  if not line:
    continue
  err_tail.append(line)
  if len(err_tail) > 12:
    err_tail = err_tail[-12:]
  # [download]  45.2% of 3.29MiB at ...
  m = re.search(r"\[download\]\s+(\d{1,3}(?:\.\d+)?)%", line)
  if m:
    pct = min(90, int(float(m.group(1))))
    if pct > last_pct:
      last_pct = pct
      progress(pct, "Downloading…")
    continue
  if "[ExtractAudio]" in line or "Deleting original" in line:
    if last_pct < 95:
      last_pct = 95
      progress(95, "Converting…")
    continue
  if line.startswith("ERROR:"):
    progress(last_pct, line[:80])

rc = proc.wait()
found = already_have()
if not found:
  cands = sorted(
    [p for p in outdir.glob(base + ".*") if p.is_file() and p.stat().st_size > 1024
     and not p.name.lower().endswith((".part", ".ytdl", ".temp"))],
    key=lambda p: p.stat().st_mtime,
    reverse=True,
  )
  found = cands[0] if cands else None

if found and found.stat().st_size > 1024:
  progress(100, "Done")
  done(True, mode, found)

err = "\n".join(err_tail)[-220:] if err_tail else (f"download-failed rc={rc}")
done(False, mode, error=err)
PY
