#!/usr/bin/env python3
import os, time, json, pathlib, subprocess, threading, queue, requests

SPOOL_DIR = "/mnt/hot/events"
PROM_FILE = "/var/lib/node_exporter/textfile_collector/media_orchestrator.prom"
SONARR = os.environ.get("SONARR_URL","http://localhost:8989")
RADARR = os.environ.get("RADARR_URL","http://localhost:7878")
LIDARR = os.environ.get("LIDARR_URL","http://localhost:8686")
HEADERS = {
  "sonarr": {"X-Api-Key": os.environ.get("SONARR_API_KEY","")},
  "radarr": {"X-Api-Key": os.environ.get("RADARR_API_KEY","")},
  "lidarr": {"X-Api-Key": os.environ.get("LIDARR_API_KEY","")},
}

def stable(path, seconds=15):
  p=pathlib.Path(path)
  if not p.exists(): return False
  s=p.stat().st_size; time.sleep(seconds)
  return p.exists() and p.stat().st_size==s

def in_use(path):
  try:
    return subprocess.run(["/run/current-system/sw/bin/fuser","-s",path], capture_output=True).returncode==0
  except Exception:
    return False

def post(url, hdrs, body):
  try:
    r=requests.post(url, headers=hdrs, json=body, timeout=10)
    return r.ok
  except Exception:
    return False

def rescan_sonarr(p): return post(f"{SONARR}/api/v3/command", HEADERS["sonarr"], {"name":"RescanFolders","folders":[p]})
def rescan_radarr(p): return post(f"{RADARR}/api/v3/command", HEADERS["radarr"], {"name":"RescanFolders","folders":[p]})
def rescan_lidarr(p): return post(f"{LIDARR}/api/v1/command", HEADERS["lidarr"], {"name":"RescanFolders","folders":[p]})

def process(evt):
  kind=(evt or {}).get("client","")
  cat=((evt or {}).get("category") or "").lower()
  path=(evt or {}).get("content_path") or (evt or {}).get("final_dir") or ""
  if not path or not os.path.exists(path): return ("ignored","no_path")
  if in_use(path) or not stable(path):     return ("defer","unstable")
  if kind in ("qbt","sab"):
    if "tv" in cat:    return ("sonarr_rescan","ok" if (rescan_sonarr(path) or rescan_sonarr(os.path.dirname(path))) else "fail")
    if "movie" in cat: return ("radarr_rescan","ok" if (rescan_radarr(path) or rescan_radarr(os.path.dirname(path))) else "fail")
    if "music" in cat: return ("lidarr_rescan","ok" if rescan_lidarr(os.path.dirname(path)) else "fail")
    return ("ignored","unknown_category")
  if kind=="slskd":
    return ("lidarr_rescan","ok" if rescan_lidarr(os.path.dirname(path)) else "fail")
  return ("ignored","unknown_client")

def tail(paths, q):
  fps=[open(p,"a+") for p in paths]
  for f in fps: f.seek(0,2)
  while True:
    for f in fps:
      line=f.readline()
      if not line: time.sleep(0.5); continue
      try: q.put(json.loads(line.strip()))
      except Exception: pass

def main():
  os.makedirs(os.path.dirname(PROM_FILE), exist_ok=True)
  paths=[os.path.join(SPOOL_DIR,"qbt.ndjson"), os.path.join(SPOOL_DIR,"sab.ndjson"), os.path.join(SPOOL_DIR,"slskd.ndjson")]
  for p in paths: open(p,"a").close()
  q=queue.Queue()
  threading.Thread(target=tail, args=(paths,q), daemon=True).start()
  counters={}
  while True:
    evt = q.get()
    a,s = process(evt)
    k=(a,s); counters[k]=counters.get(k,0)+1
    with open(PROM_FILE,"w") as f:
      f.write("# HELP media_orchestrator_events_total Events handled by orchestrator\n# TYPE media_orchestrator_events_total counter\n")
      for (aa,ss),v in sorted(counters.items()):
        f.write(f'media_orchestrator_events_total{{action="{aa}",status="{ss}"}} {v}\n')

if __name__=="__main__": main()
