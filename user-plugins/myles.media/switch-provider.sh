#!/usr/bin/env bash
set -euo pipefail
prov="${1:-}"
[[ -n $prov ]] || { echo '{"ok":false,"error":"missing-provider"}'; exit 1; }

pick() {
  python3 -c 'import sys,json
raw=sys.stdin.read()
try:
  d=json.loads(raw)
except Exception:
  print("")
  raise SystemExit(0)
r=(d.get("job") or {}).get("result") or d.get("result") or {}
pls=r.get("playlists") or []

def usable(p):
  pid=str(p.get("id") or "")
  name=str(p.get("name") or "").lower()
  if not pid: return False
  if pid.startswith("loc:"): return False
  if "location" in name and "use my" in name: return False
  return True

cands=[p for p in pls if usable(p)]
# Prefer concrete catalog/station rows (c:) over folder playlists (l:).
ranked=sorted(cands, key=lambda p: (
  0 if str(p.get("id","")).startswith("c:") else
  1 if str(p.get("id","")).startswith("l:") else
  2
))
print(ranked[0].get("id","") if ranked else "")'
}

pid="$(cliamp remote call provider.playlists --params "{\"provider\":\"$prov\",\"limit\":20}" --wait 2>/dev/null | pick || true)"
if [[ -z ${pid:-} ]]; then
  pid="$(cliamp remote call provider.catalog --params "{\"provider\":\"$prov\",\"limit\":20}" --wait 2>/dev/null | pick || true)"
fi
if [[ -z ${pid:-} ]]; then
  echo "{\"ok\":false,\"error\":\"no-playlist\",\"provider\":\"$prov\"}"
  exit 2
fi

cliamp remote call provider.load --params "{\"provider\":\"$prov\",\"playlist\":\"$pid\"}" --wait >/dev/null
# Streams sometimes need a beat before play sticks.
sleep 0.2
cliamp remote call play --wait >/dev/null || true
sleep 0.2
cliamp play >/dev/null 2>&1 || true
echo "{\"ok\":true,\"provider\":\"$prov\",\"playlist\":\"$pid\"}"
