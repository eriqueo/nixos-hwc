"""
YouTube Transcript API — hwc-server
FastAPI service for extracting YouTube transcripts.
"""

import asyncio
import logging
import os
import shutil
import uuid
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, BackgroundTasks, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field
import uvicorn

from transcript import (
    extract_video_id, is_playlist_url, fetch_metadata, fetch_playlist,
    fetch_transcript, clean_transcript, raw_transcript, format_markdown,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
logger = logging.getLogger("transcripts")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
OUTPUT_DIR = Path(os.getenv("YT_TRANSCRIPTS_OUTPUT_DIR", "/mnt/media/transcripts"))
# Whitelisted base locations the user can save into. Colon-separated, set from
# Nix (`hwc.media.youtube.transcripts.outputRoots`). The systemd sandbox only
# grants ReadWritePaths to exactly these, so an out-of-list base fails to write —
# we reject it at the API boundary first so the error is clear, not an EACCES.
OUTPUT_ROOTS = [Path(p) for p in os.getenv("YT_TRANSCRIPTS_OUTPUT_ROOTS", str(OUTPUT_DIR)).split(":") if p]
if OUTPUT_DIR not in OUTPUT_ROOTS:
    OUTPUT_ROOTS.insert(0, OUTPUT_DIR)

HOST = os.getenv("YT_TRANSCRIPTS_HOST", "127.0.0.1")
PORT = int(os.getenv("YT_TRANSCRIPTS_PORT", "8100"))
DEFAULT_MODE = os.getenv("YT_TRANSCRIPTS_DEFAULT_MODE", "clean")
LANGUAGES = os.getenv("YT_TRANSCRIPTS_LANGUAGES", "en,en-US,en-GB").split(",")

# Per-video wall-clock budget (metadata + transcript, incl. one retry).
VIDEO_TIMEOUT = 60

app = FastAPI(title="YouTube Transcripts", version="4.0.0")


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------
class TranscriptRequest(BaseModel):
    url: str
    mode: str = Field(default="", description="clean or raw")


class JobRequest(BaseModel):
    urls: list[str]
    mode: str = Field(default="")
    base: str = Field(default="", description="one of OUTPUT_ROOTS; blank = first root")
    subfolder: str = Field(default="", description="optional named folder under base")


class JobStatus(BaseModel):
    job_id: str
    status: str = "queued"
    completed: int = 0
    total: int = 0
    output_dir: str = ""
    results: list[dict] = Field(default_factory=list)
    error: str = ""


# ---------------------------------------------------------------------------
# Job store
# ---------------------------------------------------------------------------
_jobs: dict[str, JobStatus] = {}


# ---------------------------------------------------------------------------
# Output-path resolution (whitelist base + sanitized subfolder)
# ---------------------------------------------------------------------------
def _sanitize_component(name: str) -> str:
    """Sanitize a user-supplied folder name into safe path segments.

    Splits on `/` so a nested name like 'woodworking/lathe' is allowed, drops
    empty/`.`/`..` segments (no traversal), and strips odd characters per
    segment. Returns a relative path string (possibly empty).
    """
    parts = []
    for seg in name.strip().replace("\\", "/").split("/"):
        seg = seg.strip()
        if not seg or seg in (".", ".."):
            continue
        seg = "".join(c if (c.isalnum() or c in " -_.") else "_" for c in seg)[:100].strip()
        if seg:
            parts.append(seg)
    return "/".join(parts)


def resolve_base(base: str) -> Path:
    """Return the whitelisted root matching `base`, or the default root if blank."""
    if not base:
        return OUTPUT_ROOTS[0]
    candidate = Path(base)
    for root in OUTPUT_ROOTS:
        if candidate == root:
            return root
    allowed = ", ".join(str(r) for r in OUTPUT_ROOTS)
    raise ValueError(f"Base '{base}' is not an allowed location. Allowed: {allowed}")


def resolve_output_dir(base: str, subfolder: str) -> Path:
    """Resolve base + subfolder to an absolute dir contained within the base root."""
    root = resolve_base(base).resolve()
    sub = _sanitize_component(subfolder)
    out = (root / sub).resolve() if sub else root
    if out != root and root not in out.parents:
        raise ValueError("Resolved path escapes the allowed location")
    return out


# ---------------------------------------------------------------------------
# Core extraction
# ---------------------------------------------------------------------------
async def _extract(url: str, mode: str, out_dir: Path) -> dict:
    """Extract one video's transcript and write it into out_dir. Returns result dict."""
    video_id = extract_video_id(url)
    if not video_id:
        raise ValueError("Invalid YouTube URL")

    meta = await fetch_metadata(video_id)
    segments = await fetch_transcript(video_id, LANGUAGES)

    mode = mode if mode in ("clean", "raw") else DEFAULT_MODE
    text = raw_transcript(segments) if mode == "raw" else clean_transcript(segments)

    md = format_markdown(meta, text)

    safe_title = "".join(c if c.isalnum() or c in " -_" else "" for c in meta.title)[:80].strip()
    date = datetime.now().strftime("%Y-%m-%d")
    filename = f"{date} - {safe_title}.md"
    out_dir.mkdir(parents=True, exist_ok=True)
    filepath = out_dir / filename
    filepath.write_text(md, encoding="utf-8")

    return {
        "url": meta.url,
        "title": meta.title,
        "channel": meta.channel,
        "duration": f"{meta.duration}s",
        "transcript": text,
        "filename": str(filepath),
    }


# ---------------------------------------------------------------------------
# POST /transcript — single video, default location (n8n integration path)
# ---------------------------------------------------------------------------
@app.post("/transcript")
async def post_transcript(body: TranscriptRequest):
    try:
        result = await asyncio.wait_for(_extract(body.url, body.mode, OUTPUT_ROOTS[0]), timeout=VIDEO_TIMEOUT)
        return result
    except asyncio.TimeoutError:
        raise HTTPException(504, f"Extraction timed out ({VIDEO_TIMEOUT}s limit)")
    except ValueError as e:
        raise HTTPException(400, str(e))
    except Exception as e:
        logger.error(f"Extraction failed: {e}")
        raise HTTPException(500, f"Extraction failed: {e}")


# ---------------------------------------------------------------------------
# POST /job + GET /job/{id} — batch of videos and/or playlists
# ---------------------------------------------------------------------------
@app.post("/job")
async def post_job(body: JobRequest, bg: BackgroundTasks):
    urls = [u.strip() for u in body.urls if u.strip()]
    if not urls:
        raise HTTPException(400, "No URLs provided")
    try:
        out_dir = resolve_output_dir(body.base, body.subfolder)
    except ValueError as e:
        raise HTTPException(400, str(e))

    job_id = uuid.uuid4().hex[:12]
    job = JobStatus(job_id=job_id, output_dir=str(out_dir))
    _jobs[job_id] = job
    bg.add_task(_run_job, job_id, urls, body.mode, str(out_dir))
    return {"job_id": job_id, "status": "queued", "output_dir": str(out_dir)}


async def _run_job(job_id: str, urls: list[str], mode: str, out_dir_str: str):
    job = _jobs.get(job_id)
    if not job:
        return
    out_dir = Path(out_dir_str)
    job.status = "running"

    # Phase 1 — classify + expand. Each work item is (video_url, dest_dir, playlist_title).
    # Playlists expand into their own titled subfolder under out_dir.
    work: list[tuple[str, Path, str]] = []
    for raw in urls:
        video_id = extract_video_id(raw)
        if video_id:
            work.append((f"https://www.youtube.com/watch?v={video_id}", out_dir, ""))
        elif is_playlist_url(raw):
            try:
                pl = await fetch_playlist(raw)
            except Exception as e:
                job.results.append({"url": raw, "error": f"Playlist error: {e}", "playlist": ""})
                job.completed += 1
                continue
            if not pl.video_ids:
                job.results.append({"url": raw, "error": "Playlist has no videos", "playlist": pl.title})
                job.completed += 1
                continue
            dest = out_dir / (_sanitize_component(pl.title) or "playlist")
            for vid in pl.video_ids:
                work.append((f"https://www.youtube.com/watch?v={vid}", dest, pl.title))
        else:
            job.results.append({"url": raw, "error": "Invalid YouTube URL", "playlist": ""})
            job.completed += 1

    job.total = job.completed + len(work)

    # Phase 2 — extract each video sequentially (rate-limit friendly).
    for video_url, dest, playlist_title in work:
        try:
            result = await asyncio.wait_for(_extract(video_url, mode, dest), timeout=VIDEO_TIMEOUT)
            result["playlist"] = playlist_title
            job.results.append(result)
        except Exception as e:
            job.results.append({"url": video_url, "error": str(e), "playlist": playlist_title})
        job.completed += 1

    job.status = "complete"


@app.get("/job/{job_id}")
async def get_job(job_id: str):
    job = _jobs.get(job_id)
    if not job:
        raise HTTPException(404, "Job not found")
    return job.model_dump()


# ---------------------------------------------------------------------------
# GET /config — locations + defaults for the UI
# ---------------------------------------------------------------------------
@app.get("/config")
async def config():
    return {"roots": [str(r) for r in OUTPUT_ROOTS], "default_mode": DEFAULT_MODE}


# ---------------------------------------------------------------------------
# GET /health
# ---------------------------------------------------------------------------
@app.get("/health")
async def health():
    disk = shutil.disk_usage(OUTPUT_DIR) if OUTPUT_DIR.exists() else None
    return {
        "status": "healthy",
        "disk_free_gb": round(disk.free / (1024**3), 1) if disk else None,
        "output_dir": str(OUTPUT_DIR),
        "output_roots": [str(r) for r in OUTPUT_ROOTS],
    }


# ---------------------------------------------------------------------------
# GET / — Web UI
# ---------------------------------------------------------------------------
@app.get("/", response_class=HTMLResponse)
async def ui():
    return """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>YouTube Transcripts</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; background: #f5f5f5; color: #222; padding: 1.5rem;
         display: flex; flex-direction: column; align-items: center; min-height: 100vh; }
  h1 { font-size: 1.3rem; margin-bottom: 1rem; }
  .card { background: #fff; border-radius: 10px; padding: 1.25rem; width: 100%; max-width: 720px;
          box-shadow: 0 1px 4px rgba(0,0,0,.1); margin-bottom: 1rem; }
  .card h2 { font-size: .9rem; color: #666; margin-bottom: .6rem; }
  label { display: block; font-size: .78rem; color: #666; margin-bottom: .25rem; }
  .urlrow { display: flex; gap: .4rem; margin-bottom: .5rem; }
  input[type=text], select { padding: .6rem .7rem; border-radius: 7px; border: 1px solid #ccc;
                             font-size: 1rem; outline: none; }
  input[type=text] { flex: 1; }
  input:focus, select:focus { border-color: #2563eb; }
  .urlrow .del { background: #f3f4f6; color: #6b7280; border: 1px solid #e5e7eb; border-radius: 7px;
                 min-width: 44px; font-size: 1.1rem; cursor: pointer; }
  .urlrow .del:hover { background: #fee2e2; color: #dc2626; }
  .addbtn { background: #eef2ff; color: #2563eb; border: 1px dashed #93c5fd; border-radius: 7px;
            padding: .55rem 1rem; font-size: .85rem; font-weight: 600; cursor: pointer; margin-bottom: 1rem; }
  .addbtn:hover { background: #e0e7ff; }
  .opts { display: grid; grid-template-columns: 1fr 2fr; gap: .6rem; margin-bottom: .5rem; }
  .opts .full { grid-column: 1 / -1; }
  .opts select, .opts input[type=text] { width: 100%; font-size: .9rem; }
  .go { padding: .7rem 1.4rem; border-radius: 7px; border: none; background: #2563eb; color: #fff;
        font-weight: 600; font-size: 1rem; cursor: pointer; min-height: 46px; width: 100%; margin-top: .4rem; }
  .go:hover { background: #1d4ed8; }
  .go:disabled { opacity: .5; cursor: wait; }
  .msg { font-size: .85rem; color: #666; min-height: 1.2em; margin: .6rem 0 .2rem; }
  .msg.err { color: #dc2626; }
  .results { list-style: none; margin-top: .3rem; }
  .results li { font-size: .85rem; padding: .5rem .1rem; border-bottom: 1px solid #f0f0f0;
                display: flex; gap: .5rem; align-items: flex-start; }
  .results .body { flex: 1; min-width: 0; }
  .results .ok .title { color: #111; font-weight: 600; }
  .results .path { color: #059669; word-break: break-all; font-size: .78rem; }
  .results .fail .title { color: #dc2626; }
  .results .fail .path { color: #b91c1c; }
  .badge { display: inline-block; background: #ede9fe; color: #6d28d9; border-radius: 5px;
           padding: .05rem .4rem; font-size: .68rem; margin-right: .35rem; vertical-align: middle; }
  .copy { background: #e5e7eb; color: #222; border: none; border-radius: 6px; padding: .35rem .7rem;
          font-size: .78rem; cursor: pointer; }
  .copy:hover { background: #d1d5db; }
</style>
</head>
<body>
<h1>YouTube Transcripts</h1>

<div class="card">
  <h2>URLs — videos or playlists</h2>
  <div id="urls"></div>
  <button class="addbtn" id="add" onclick="addRow()">+ URL</button>

  <div class="opts">
    <div>
      <label>Format</label>
      <select id="mode">
        <option value="clean">Clean</option>
        <option value="raw">Raw</option>
      </select>
    </div>
    <div>
      <label>Save location</label>
      <select id="base"></select>
    </div>
    <div class="full">
      <label>Folder name (optional — nest with "/", e.g. woodworking/lathe)</label>
      <input type="text" id="subfolder" placeholder="leave blank to save in the location root">
    </div>
  </div>

  <button class="go" id="go" onclick="run()">Extract</button>
  <div class="msg" id="msg"></div>
  <ul class="results" id="results"></ul>
</div>

<script>
const $=id=>document.getElementById(id);
let _results=[];

function rowHtml() {
  return `<div class="urlrow">
    <input type="text" placeholder="Paste a YouTube video or playlist URL..." class="u">
    <button class="del" onclick="delRow(this)" title="remove">&times;</button>
  </div>`;
}
function addRow() {
  $('urls').insertAdjacentHTML('beforeend', rowHtml());
  const rows=$('urls').querySelectorAll('.u');
  rows[rows.length-1].focus();
  rows[rows.length-1].addEventListener('keydown',e=>{if(e.key==='Enter')run();});
}
function delRow(btn) {
  const rows=$('urls').querySelectorAll('.urlrow');
  if(rows.length<=1){ btn.closest('.urlrow').querySelector('.u').value=''; return; }
  btn.closest('.urlrow').remove();
}

async function loadConfig() {
  try {
    const r=await fetch('/config'); const d=await r.json();
    $('base').innerHTML=d.roots.map(p=>`<option value="${p}">${p}</option>`).join('');
    if(d.default_mode) $('mode').value=d.default_mode==='raw'?'raw':'clean';
  } catch(e) { $('base').innerHTML='<option value="">(default)</option>'; }
}

function renderResults(status) {
  $('results').innerHTML='';
  _results.forEach((r,i)=>{
    const li=document.createElement('li');
    const badge=r.playlist?`<span class="badge">${r.playlist}</span>`:'';
    if(r.error){
      li.className='fail';
      li.innerHTML=`<div class="body"><div class="title">${badge}${r.url||''}</div><div class="path">${r.error}</div></div>`;
    } else {
      li.className='ok';
      li.innerHTML=`<div class="body"><div class="title">${badge}${r.title||''}</div><div class="path">${r.filename||''}</div></div>`;
      const b=document.createElement('button'); b.className='copy'; b.textContent='Copy';
      b.onclick=()=>{navigator.clipboard.writeText(_results[i].transcript||'');b.textContent='Copied!';setTimeout(()=>b.textContent='Copy',1200);};
      li.appendChild(b);
    }
    $('results').appendChild(li);
  });
}

async function run() {
  const urls=[...$('urls').querySelectorAll('.u')].map(i=>i.value.trim()).filter(Boolean);
  if(!urls.length){ $('msg').className='msg err'; $('msg').textContent='Add at least one URL.'; return; }
  $('go').disabled=true; _results=[];
  $('msg').className='msg'; $('msg').textContent='Submitting '+urls.length+' URL(s)...';
  $('results').innerHTML='';
  try {
    const r=await fetch('/job',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({urls,mode:$('mode').value,base:$('base').value,subfolder:$('subfolder').value.trim()})});
    if(!r.ok){const e=await r.json();throw new Error(e.detail||r.statusText);}
    const d=await r.json();
    $('msg').textContent='Saving to '+d.output_dir+' — expanding...';
    const poll=setInterval(async()=>{
      const pr=await fetch('/job/'+d.job_id);
      if(!pr.ok) return;
      const pd=await pr.json();
      _results=pd.results;
      const totalTxt=pd.total?('/'+pd.total):'';
      $('msg').textContent=(pd.status==='complete'?'Done ':'Processing... ')
        +'('+pd.completed+totalTxt+') → '+pd.output_dir;
      renderResults(pd.status);
      if(pd.status==='complete'){clearInterval(poll);$('go').disabled=false;}
    },1500);
  } catch(e) {
    $('msg').className='msg err'; $('msg').textContent=e.message; $('go').disabled=false;
  }
}

addRow();
loadConfig();
</script>
</body>
</html>"""


if __name__ == "__main__":
    uvicorn.run(app, host=HOST, port=PORT, workers=1, log_level="info")
