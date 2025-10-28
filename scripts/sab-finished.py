#!/usr/bin/env python3
import os, json, time
spool = "/mnt/hot/events/sab.ndjson"
env = os.environ
payload = {
  "client": "sab",
  "time": int(time.time()),
  "status": env.get("SAB_PP_STATUS",""),
  "nzb_name": env.get("NZBNAME",""),
  "final_dir": env.get("SAB_FINAL_DIR") or env.get("SAB_COMPLETE_DIR",""),
  "category": env.get("SAB_CAT",""),
}
with open(spool,"a") as f:
  f.write(json.dumps(payload)+"\n")
