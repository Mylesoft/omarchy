#!/usr/bin/env bash
set -euo pipefail
raw="${1:-{}}"
python3 - "$raw" <<'PY'
import json, subprocess, sys
try: hit=json.loads(sys.argv[1])
except Exception: hit={}
url=str(hit.get("path") or "")
if not url.startswith(("https://www.youtube.com/", "https://youtu.be/")):
 print(json.dumps({"ok":False,"error":"unsupported-url"})); raise SystemExit(2)
cmd=["yt-dlp","-f","bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio[ext=webm]/bestaudio[acodec^=opus]/bestaudio/best","-g","--no-warnings",url]
try: p=subprocess.run(cmd,capture_output=True,text=True,timeout=55)
except Exception as e:
 print(json.dumps({"ok":False,"error":str(e)[:200]})); raise SystemExit(2)
stream=next((x.strip() for x in p.stdout.splitlines() if x.strip().startswith("https://")),"")
if p.returncode or not stream:
 print(json.dumps({"ok":False,"error":(p.stderr or "yt-dlp could not resolve audio")[-300:]})); raise SystemExit(2)
try:
 p=subprocess.run(["cliamp","remote","call","url.load","--params",json.dumps({"path":stream,"play":True}),"--wait"],capture_output=True,text=True,timeout=60)
 d=json.loads(p.stdout or "{}")
 job=d.get("job") or {}
 ok=p.returncode==0 and (d.get("ok") is True or job.get("state") in ("succeeded","running","queued","pending") or (job.get("result") or {}).get("ok") is True)
 if ok: subprocess.run(["cliamp","remote","call","play","--params","{}"],capture_output=True,timeout=8)
 print(json.dumps({"ok":ok,"error":"" if ok else str(d.get("error") or job.get("error") or "cliamp audio start failed")[:200]}))
 raise SystemExit(0 if ok else 2)
except Exception as e:
 print(json.dumps({"ok":False,"error":str(e)[:200]})); raise SystemExit(2)
PY
