#!/usr/bin/env bash
# Export / import media library (favourites + recents + folders).
# Usage:
#   library.sh export <stateDir>
#   library.sh import <stateDir> [bundlePath]
set -euo pipefail
op="${1:-}"
state="${2:-}"
extra="${3:-}"

if [[ -z $op || -z $state ]]; then
  printf '%s\n' '{"ok":false,"error":"usage: library.sh export|import <stateDir> [path]"}'
  exit 0
fi

mkdir -p "$state"
fav="$state/favourites.json"
rec="$state/recents.json"
fld="$state/favourite-folders.json"
downloads="${HOME}/Downloads"
mkdir -p "$downloads"

export_bundle() {
  local out="$downloads/myles-media-library-$(date +%Y%m%d-%H%M%S).json"
  python3 - <<PY
import json, os
state = os.environ["LIB_STATE"]
out = os.environ["LIB_OUT"]
def load(path, default):
  try:
    with open(path, "r", encoding="utf-8") as f:
      return json.load(f)
  except Exception:
    return default
bundle = {
  "version": 1,
  "kind": "myles.media.library",
  "favourites": load(os.path.join(state, "favourites.json"), {"version": 1, "items": []}),
  "recents": load(os.path.join(state, "recents.json"), {"version": 1, "items": []}),
  "folders": load(os.path.join(state, "favourite-folders.json"), {"version": 1, "folders": []}),
}
with open(out, "w", encoding="utf-8") as f:
  json.dump(bundle, f, indent=2)
print(json.dumps({"ok": True, "path": out}))
PY
}

import_bundle() {
  local src="$1"
  if [[ -z $src ]]; then
    # Newest matching export in Downloads
    src="$(ls -1t "$downloads"/myles-media-library-*.json 2>/dev/null | head -1 || true)"
  fi
  if [[ -z $src || ! -f $src ]]; then
    printf '%s\n' '{"ok":false,"error":"no-bundle-found"}'
    exit 0
  fi
  export LIB_SRC="$src"
  export LIB_DOWNLOADS="$downloads"
  python3 - <<PY
import json, os
from pathlib import Path
state = os.environ["LIB_STATE"]
src = os.environ["LIB_SRC"]
downloads = Path(os.environ.get("LIB_DOWNLOADS") or str(Path.home() / "Downloads")).resolve()
src_path = Path(src).resolve()
# Confine imports to ~/Downloads (or explicit myles-media-*.json under home).
allowed = False
try:
  src_path.relative_to(downloads)
  allowed = src_path.name.startswith("myles-media-") and src_path.suffix == ".json"
except Exception:
  home = Path.home().resolve()
  try:
    src_path.relative_to(home)
    allowed = src_path.name.startswith("myles-media-") and src_path.suffix == ".json"
  except Exception:
    allowed = False
if not allowed:
  print(json.dumps({"ok": False, "error": "refuse-import-path"}))
  raise SystemExit(0)
with open(src_path, "r", encoding="utf-8") as f:
  bundle = json.load(f)
if not isinstance(bundle, dict):
  print(json.dumps({"ok": False, "error": "bad-bundle"}))
  raise SystemExit(0)
kind = str(bundle.get("kind") or "")
if kind and "myles.media" not in kind and "library" not in kind and "station" not in kind:
  # Accept legacy bundles without kind, reject unrelated JSON.
  if "favourites" not in bundle and "items" not in bundle:
    print(json.dumps({"ok": False, "error": "not-a-media-bundle"}))
    raise SystemExit(0)
fav = bundle.get("favourites") or {"version": 1, "items": []}
rec = bundle.get("recents") or {"version": 1, "items": []}
fld = bundle.get("folders") or {"version": 1, "folders": []}
# Never write outside state dir.
state_path = Path(state).resolve()
for name, data in (
  ("favourites.json", fav),
  ("recents.json", rec),
  ("favourite-folders.json", fld),
):
  path = (state_path / name).resolve()
  try:
    path.relative_to(state_path)
  except Exception:
    print(json.dumps({"ok": False, "error": "refuse-state-path"}))
    raise SystemExit(0)
  with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
print(json.dumps({"ok": True, "path": str(src_path)}))
PY
}

export LIB_STATE="$state"
case "$op" in
  export)
    export LIB_OUT="$downloads/myles-media-library-$(date +%Y%m%d-%H%M%S).json"
    export_bundle
    ;;
  import)
    import_bundle "$extra"
    ;;
  *)
    printf '%s\n' '{"ok":false,"error":"unknown-op"}'
    ;;
esac
