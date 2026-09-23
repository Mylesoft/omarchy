#!/usr/bin/env bash
# List local audio files for the Media plugin's Local hub.
# Usage: list-local-media.sh [query] [limit] [folder-filter]
# Config: ~/.local/state/omarchy/media/settings.json → localRoots
set -euo pipefail

export LOCAL_QUERY="${1:-}"
export LOCAL_LIMIT="${2:-500}"
export LOCAL_FOLDER="${3:-}"

python3 <<'PY'
import json, os
from pathlib import Path

EXTS = {
  ".mp3", ".flac", ".m4a", ".aac", ".ogg", ".opus", ".wav",
  ".wma", ".aiff", ".aif", ".alac", ".ape", ".wv", ".mp4", ".mka",
  ".webm", ".mkv", ".mov", ".avi",
}

query = (os.environ.get("LOCAL_QUERY") or "").strip().lower()
folder_filter = (os.environ.get("LOCAL_FOLDER") or "").strip().lower()
try:
  limit = max(1, min(2000, int(os.environ.get("LOCAL_LIMIT") or "500")))
except ValueError:
  limit = 500

home = Path.home()
settings_path = home / ".local/state/omarchy/media/settings.json"
extra_roots = []
try:
  settings = json.loads(settings_path.read_text())
  for r in settings.get("localRoots") or []:
    if r:
      extra_roots.append(str(r))
except Exception:
  pass

roots = []
for raw in [
  os.environ.get("XDG_MUSIC_DIR") or str(home / "Music"),
  str(home / "Downloads" / "Media"),
  *extra_roots,
  *(p for p in (os.environ.get("OMARCHY_MEDIA_LOCAL_DIRS") or "").split(":") if p.strip()),
]:
  p = Path(raw).expanduser()
  if p.is_dir() and p not in roots:
    roots.append(p)

downloads = home / "Downloads"
if downloads.is_dir() and downloads not in roots:
  roots.append(downloads)

def title_artist(path: Path):
  stem = path.stem.strip()
  if " - " in stem:
    artist, title = stem.split(" - ", 1)
    artist, title = artist.strip(), title.strip()
    if artist and title:
      return title, artist
  return stem or path.name, ""

def folder_label(path: Path, roots_list):
  for root in roots_list:
    try:
      rel = path.relative_to(root)
      parent = rel.parent.as_posix()
      if parent and parent != ".":
        return f"{root.name}/{parent}"
      return root.name
    except ValueError:
      continue
  return path.parent.name

seen = set()
files = []
folders = set()
for root in roots:
  only_top = root.name == "Downloads" and root.parent == home
  try:
    it = root.iterdir() if only_top else root.rglob("*")
  except OSError:
    continue
  for p in it:
    try:
      if not p.is_file():
        continue
      if p.suffix.lower() not in EXTS:
        continue
      if only_top and p.parent != root:
        continue
      key = str(p.resolve())
      if key in seen:
        continue
      seen.add(key)
      try:
        st = p.stat()
        mtime = st.st_mtime
        size = st.st_size
      except OSError:
        continue
      if size < 1024:
        continue
      title, artist = title_artist(p)
      folder = folder_label(p, roots)
      folders.add(folder)
      hay = f"{title} {artist} {p.name} {folder}".lower()
      if query and query not in hay:
        continue
      if folder_filter and folder_filter not in folder.lower():
        continue
      files.append({
        "path": key,
        "title": title,
        "artist": artist,
        "mtime": mtime,
        "size": size,
        "folder": folder,
      })
    except OSError:
      continue

files.sort(key=lambda t: (-t["mtime"], t["title"].lower()))
files = files[:limit]

tracks = []
for t in files:
  size_mb = t["size"] / (1024 * 1024)
  size_s = f"{size_mb:.1f} MB" if size_mb >= 1 else f"{max(1, int(t['size'] / 1024))} KB"
  detail = " · ".join(x for x in ["Local", t["folder"], size_s] if x)
  tracks.append({
    "title": t["title"],
    "artist": t["artist"],
    "album": t["folder"],
    "path": t["path"],
    "artUrl": "",
    "stream": False,
    "feed": False,
    "kind": "local",
    "albumId": "",
    "provider": "local",
    "providerLabel": "Local",
    "detail": detail,
    "folder": t["folder"],
    "sizeLabel": size_s,
    "bytes": t["size"],
    "track": {
      "title": t["title"],
      "artist": t["artist"],
      "path": t["path"],
      "stream": False,
    },
  })

print(json.dumps({
  "ok": True,
  "provider": "local",
  "providers": ["local"],
  "hitProviders": ["local"] if tracks else [],
  "total": len(tracks),
  "tracks": tracks,
  "folders": sorted(folders),
  "roots": [str(r) for r in roots],
  "error": "" if tracks else (
    "No local audio — add files to ~/Music or ~/Downloads/Media"
    if not query else "No matching local files"
  ),
}))
PY
