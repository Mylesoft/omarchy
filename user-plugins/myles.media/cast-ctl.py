#!/usr/bin/env python3
"""Small user-session Chromecast/DLNA discovery and sender for myles.media."""
import html, http.server, json, os, re, signal, socket, subprocess, sys, threading, time, urllib.parse, urllib.request, uuid


def local_ip(peer="8.8.8.8"):
  s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
  try:
    s.connect((peer, 80)); return s.getsockname()[0]
  except Exception:
    return "127.0.0.1"
  finally: s.close()


def discover_dlna():
  msg = ('M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n'
         'MAN: "ssdp:discover"\r\nMX: 2\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n').encode()
  s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
  s.settimeout(0.25); s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
  found = {}; end = time.time() + 2.5
  try:
    s.sendto(msg, ("239.255.255.250", 1900))
    while time.time() < end:
      try: data, addr = s.recvfrom(65535)
      except socket.timeout: continue
      headers = {}
      for line in data.decode("latin1", "ignore").split("\r\n")[1:]:
        if ":" in line:
          k, v = line.split(":", 1); headers[k.lower().strip()] = v.strip()
      loc = headers.get("location", "")
      if not loc or loc in found: continue
      try:
        with urllib.request.urlopen(loc, timeout=2) as r: xml = r.read(512000)
        import xml.etree.ElementTree as ET
        root = ET.fromstring(xml)
        vals = {e.tag.split("}")[-1]: (e.text or "").strip() for e in root.iter()}
        base = vals.get("URLBase") or loc
        service = next((e for e in root.iter() if e.tag.split("}")[-1] == "service"
          and any(x.tag.split("}")[-1] == "serviceType" and "AVTransport" in (x.text or "") for x in e)), None)
        if not service: continue
        fields = {e.tag.split("}")[-1]: (e.text or "").strip() for e in service}
        ctl = urllib.parse.urljoin(base, fields.get("controlURL", ""))
        name = vals.get("friendlyName") or addr[0]
        ident = headers.get("usn", loc)
        found[ident] = {"id": ident, "name": name, "type": "dlna", "location": loc,
          "controlUrl": ctl, "host": addr[0]}
      except Exception: pass
  finally: s.close()
  return list(found.values())


def discover():
  devices = discover_dlna(); error = ""
  try:
    import pychromecast
    casts, browser = pychromecast.get_chromecasts(timeout=3)
    try:
      for c in casts:
        devices.append({"id": str(c.uuid), "name": c.name, "type": "chromecast", "host": c.host})
    finally: pychromecast.discovery.stop_discovery(browser)
  except ImportError:
    error = "Chromecast support needs pychromecast and zeroconf installed"
  except Exception as e:
    error = "Chromecast discovery: " + str(e)[:140]
  notice = error or ("No receiver announced on this Wi-Fi. Power it on, connect it to the same network, then retry." if not devices else "")
  return {"ok": True, "devices": devices, "notice": notice}


class RangeHandler(http.server.BaseHTTPRequestHandler):
  state_file = ""
  path_to_serve = ""
  def do_HEAD(self): self.serve_file(head=True)
  def do_GET(self): self.serve_file(head=False)
  def serve_file(self, head=False):
    try:
      path = self.path_to_serve
      if self.state_file:
        with open(self.state_file) as f: state = json.load(f)
        if self.client_address[0] != str(state.get("receiver") or ""):
          self.send_error(403); return
        path = state.get("path") or path
      size = os.path.getsize(path); start, end = 0, size - 1
      h = self.headers.get("Range", "")
      m = re.match(r"bytes=(\d*)-(\d*)", h)
      if m:
        start = int(m.group(1) or 0); end = min(end, int(m.group(2) or end))
        self.send_response(206); self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
      else: self.send_response(200)
      self.send_header("Content-Type", "video/mp4"); self.send_header("Accept-Ranges", "bytes")
      self.send_header("Content-Length", str(max(0, end-start+1))); self.send_header("Access-Control-Allow-Origin", "*")
      self.end_headers()
      if not head:
        with open(path, "rb") as f:
          f.seek(start); remaining=end-start+1
          while remaining:
            b=f.read(min(1024*1024,remaining))
            if not b: break
            self.wfile.write(b); remaining-=len(b)
    except (BrokenPipeError, ConnectionResetError): pass
    except Exception: self.send_error(404)
  def log_message(self, *_): pass


def serve(state_file, bind_ip, port):
  RangeHandler.state_file = os.path.abspath(state_file)
  http.server.ThreadingHTTPServer((bind_ip, int(port)), RangeHandler).serve_forever()


def media_url(path, target):
  if path.startswith(("http://", "https://")):
    if "youtube.com/" in path or "youtu.be/" in path:
      p = subprocess.run(["yt-dlp", "-f", "best[ext=mp4][height<=?720]/best[height<=?720]/best", "-g", "--no-warnings", path], capture_output=True, text=True, timeout=50)
      url = next((x.strip() for x in p.stdout.splitlines() if x.strip().startswith("http")), "")
      if p.returncode or not url: raise RuntimeError("yt-dlp could not resolve a castable video stream")
      return url
    return path
  path = os.path.abspath(path)
  if not os.path.isfile(path): raise RuntimeError("The current media item has no castable file or URL")
  port = 18743
  receiver = str(target.get("host") or "")
  if not receiver: raise RuntimeError("The receiver has no LAN address")
  ip = local_ip(receiver)
  # Serve only on the chosen LAN interface and authorize requests from the
  # selected receiver IP. A fixed port allows an equally narrow firewall rule.
  state_dir = os.path.expanduser("~/.local/state/omarchy/media")
  os.makedirs(state_dir, exist_ok=True)
  stamp = os.path.join(state_dir, "cast-http.json")
  d = {}
  try:
    with open(stamp) as f: d = json.load(f)
  except Exception: pass
  pid = int(d.get("pid") or 0)
  alive = False
  if pid:
    try:
      os.kill(pid, 0)
      with open(f"/proc/{pid}/cmdline", "rb") as f: command = f.read()
      alive = b"cast-ctl.py" in command and b"serve" in command
    except Exception: pass
  if alive and d.get("version") == 2 and int(d.get("port") or 0) == port and d.get("bindIp") == ip:
    d.update({"path": path, "receiver": receiver})
    tmp = stamp + ".tmp"
    with open(tmp, "w") as f: json.dump(d, f)
    os.replace(tmp, stamp)
  else:
    if alive:
      try: os.kill(pid, signal.SIGTERM)
      except Exception: pass
      for _ in range(20):
        try: os.kill(pid, 0); time.sleep(0.05)
        except Exception: break
    probe = socket.socket()
    try: probe.bind((ip, port))
    except OSError as e: raise RuntimeError(f"Cast media port {port} is unavailable: {e}")
    finally: probe.close()
    d = {"version": 2, "port": port, "bindIp": ip, "receiver": receiver, "path": path}
    tmp = stamp + ".tmp"
    with open(tmp, "w") as f: json.dump(d, f)
    os.replace(tmp, stamp)
    p = subprocess.Popen([sys.executable, os.path.abspath(__file__), "serve", stamp, ip, str(port)],
      stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    d["pid"] = p.pid
    with open(tmp, "w") as f: json.dump(d, f)
    os.replace(tmp, stamp)
    for _ in range(30):
      try:
        with socket.create_connection((ip, port), timeout=0.15): break
      except OSError: time.sleep(0.1)
    else: raise RuntimeError("Cast media server failed to start")
  return f"http://{ip}:{port}/media"


def soap(url, service, action, args):
  body = '<u:'+action+' xmlns:u="'+service+'">'+''.join('<'+k+'>'+html.escape(str(v))+'</'+k+'>' for k,v in args.items())+'</u:'+action+'>'
  req=urllib.request.Request(url, data=('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'+body+'</s:Body></s:Envelope>').encode(),
    headers={"Content-Type":"text/xml; charset=\"utf-8\"", "SOAPACTION":f'"{service}#{action}"'}, method="POST")
  with urllib.request.urlopen(req,timeout=8) as r: r.read(4096)


def cast(target, hit):
  path=str(hit.get("path") or ""); title=str(hit.get("title") or "Video")
  if not path: raise RuntimeError("Nothing is playing")
  url=media_url(path,target)
  if target.get("type")=="chromecast":
    try: import pychromecast
    except ImportError: raise RuntimeError("Chromecast needs pychromecast + zeroconf; install those Python packages first")
    casts,browser=pychromecast.get_chromecasts(timeout=4)
    try:
      c=next((x for x in casts if str(x.uuid)==str(target.get("id"))),None)
      if not c: raise RuntimeError("Chromecast receiver was not rediscovered")
      c.wait(8); c.media_controller.play_media(url,"video/mp4",title=title,thumb=hit.get("artUrl") or None); c.media_controller.block_until_active(10)
    finally: pychromecast.discovery.stop_discovery(browser)
  else:
    service="urn:schemas-upnp-org:service:AVTransport:1"
    didl=('<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">'
      '<item id="0" parentID="0" restricted="1"><dc:title>'+html.escape(title)+'</dc:title><upnp:class>object.item.videoItem</upnp:class><res protocolInfo="http-get:*:video/mp4:*">'+html.escape(url)+'</res></item></DIDL-Lite>')
    soap(target["controlUrl"],service,"SetAVTransportURI",{"InstanceID":0,"CurrentURI":url,"CurrentURIMetaData":didl})
    soap(target["controlUrl"],service,"Play",{"InstanceID":0,"Speed":1})
  return {"ok":True,"name":target.get("name","Receiver")}

if __name__ == "__main__":
  try:
    if sys.argv[1] == "discover": print(json.dumps(discover()))
    elif sys.argv[1] == "cast": print(json.dumps(cast(json.loads(sys.argv[2]),json.loads(sys.argv[3]))))
    elif sys.argv[1] == "serve": serve(sys.argv[2],sys.argv[3],sys.argv[4])
    else: print(json.dumps({"ok":False,"error":"usage: cast-ctl.py discover|cast"})); raise SystemExit(2)
  except Exception as e:
    print(json.dumps({"ok":False,"error":str(e)[:300]})); raise SystemExit(2)
