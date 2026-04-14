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
from typing import Optional

from fastapi import FastAPI, BackgroundTasks, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field
import uvicorn

from transcript import (
    extract_video_id, is_playlist_url, fetch_metadata, fetch_transcript,
    clean_transcript, raw_transcript, format_markdown,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
logger = logging.getLogger("yt-transcripts-api")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
OUTPUT_DIR = Path(os.getenv("YT_TRANSCRIPTS_OUTPUT_DIR", "/mnt/media/transcripts"))
HOST = os.getenv("YT_TRANSCRIPTS_HOST", "127.0.0.1")
PORT = int(os.getenv("YT_TRANSCRIPTS_PORT", "8100"))
DEFAULT_MODE = os.getenv("YT_TRANSCRIPTS_DEFAULT_MODE", "clean")
LANGUAGES = os.getenv("YT_TRANSCRIPTS_LANGUAGES", "en,en-US,en-GB").split(",")

app = FastAPI(title="YouTube Transcripts", version="3.0.0")


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------
class TranscriptRequest(BaseModel):
    url: str
    mode: str = Field(default="", description="clean or raw")


class JobRequest(BaseModel):
    urls: list[str]
    mode: str = Field(default="")


class JobStatus(BaseModel):
    job_id: str
    status: str = "queued"
    completed: int = 0
    total: int = 0
    results: list[dict] = Field(default_factory=list)
    error: str = ""


# ---------------------------------------------------------------------------
# Job store
# ---------------------------------------------------------------------------
_jobs: dict[str, JobStatus] = {}


# ---------------------------------------------------------------------------
# Core extraction
# ---------------------------------------------------------------------------
async def _extract(url: str, mode: str) -> dict:
    """Extract transcript from a single video. Returns result dict."""
    video_id = extract_video_id(url)
    if not video_id:
        raise ValueError("Invalid YouTube URL")

    # Single yt-dlp call for metadata
    meta = await fetch_metadata(video_id)

    # Fetch transcript (youtube-transcript-api primary, yt-dlp VTT fallback)
    segments = await fetch_transcript(video_id, LANGUAGES)

    # Clean or raw
    mode = mode if mode in ("clean", "raw") else DEFAULT_MODE
    if mode == "raw":
        text = raw_transcript(segments)
    else:
        text = clean_transcript(segments)

    # Format markdown
    md = format_markdown(meta, text)

    # Save to disk
    safe_title = "".join(c if c.isalnum() or c in " -_" else "" for c in meta.title)[:80].strip()
    date = datetime.now().strftime("%Y-%m-%d")
    filename = f"{date} - {safe_title}.md"
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    filepath = OUTPUT_DIR / filename
    filepath.write_text(md, encoding="utf-8")

    return {
        "title": meta.title,
        "channel": meta.channel,
        "duration": f"{meta.duration}s",
        "transcript": text,
        "filename": str(filepath),
    }


# ---------------------------------------------------------------------------
# POST /transcript
# ---------------------------------------------------------------------------
@app.post("/transcript")
async def post_transcript(body: TranscriptRequest):
    try:
        result = await asyncio.wait_for(_extract(body.url, body.mode), timeout=30)
        return result
    except asyncio.TimeoutError:
        raise HTTPException(504, "Extraction timed out (30s limit)")
    except ValueError as e:
        raise HTTPException(400, str(e))
    except Exception as e:
        logger.error(f"Extraction failed: {e}")
        raise HTTPException(500, f"Extraction failed: {e}")


# ---------------------------------------------------------------------------
# POST /job + GET /job/{id}
# ---------------------------------------------------------------------------
@app.post("/job")
async def post_job(body: JobRequest, bg: BackgroundTasks):
    if not body.urls:
        raise HTTPException(400, "No URLs provided")
    job_id = uuid.uuid4().hex[:12]
    job = JobStatus(job_id=job_id, total=len(body.urls))
    _jobs[job_id] = job
    bg.add_task(_run_job, job_id, body.urls, body.mode)
    return {"job_id": job_id, "status": "queued", "total": len(body.urls)}


async def _run_job(job_id: str, urls: list[str], mode: str):
    job = _jobs.get(job_id)
    if not job:
        return
    job.status = "running"
    for url in urls:
        try:
            result = await asyncio.wait_for(_extract(url, mode), timeout=30)
            job.results.append(result)
        except Exception as e:
            job.results.append({"url": url, "error": str(e)})
        job.completed += 1
    job.status = "complete"


@app.get("/job/{job_id}")
async def get_job(job_id: str):
    job = _jobs.get(job_id)
    if not job:
        raise HTTPException(404, "Job not found")
    return job.model_dump()


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
  .card { background: #fff; border-radius: 10px; padding: 1.25rem; width: 100%; max-width: 700px;
          box-shadow: 0 1px 4px rgba(0,0,0,.1); margin-bottom: 1rem; }
  .card h2 { font-size: .9rem; color: #666; margin-bottom: .6rem; }
  .row { display: flex; gap: .4rem; margin-bottom: .6rem; }
  input[type=text] { flex: 1; padding: .65rem .8rem; border-radius: 7px; border: 1px solid #ccc;
                     font-size: 1rem; outline: none; }
  input:focus { border-color: #2563eb; }
  select { padding: .65rem .6rem; border-radius: 7px; border: 1px solid #ccc; font-size: .9rem; }
  button { padding: .65rem 1.2rem; border-radius: 7px; border: none; background: #2563eb; color: #fff;
           font-weight: 600; font-size: .95rem; cursor: pointer; min-height: 44px; }
  button:hover { background: #1d4ed8; }
  button:disabled { opacity: .4; cursor: wait; }
  .msg { font-size: .85rem; color: #666; min-height: 1.2em; margin-bottom: .4rem; }
  .msg.err { color: #dc2626; }
  .filepath { font-size: .8rem; color: #059669; background: #f0fdf4; border: 1px solid #bbf7d0;
              border-radius: 6px; padding: .4rem .7rem; word-break: break-all; user-select: all;
              -webkit-user-select: all; display: none; margin-bottom: .5rem; }
  .actions { display: flex; gap: .4rem; margin-bottom: .5rem; display: none; }
  .actions button { background: #e5e7eb; color: #222; font-size: .85rem; padding: .5rem 1rem; }
  .actions button:hover { background: #d1d5db; }
  .transcript { background: #fafafa; border: 1px solid #e5e7eb; border-radius: 7px; padding: 1rem;
                max-height: 60vh; overflow-y: auto; white-space: pre-wrap; font-size: .9rem;
                line-height: 1.6; display: none; }
  .batch-list { list-style: none; }
  .batch-list li { font-size: .85rem; padding: .3rem 0; border-bottom: 1px solid #f0f0f0; }
  .batch-list .ok { color: #059669; }
  .batch-list .fail { color: #dc2626; }
</style>
</head>
<body>
<h1>YouTube Transcripts</h1>

<div class="card">
  <h2>Single Video</h2>
  <div class="row">
    <input type="text" id="url" placeholder="Paste YouTube URL..." autofocus>
    <select id="mode">
      <option value="clean">Clean</option>
      <option value="raw">Raw</option>
    </select>
    <button id="go" onclick="extract()">Go</button>
  </div>
  <div class="msg" id="msg"></div>
  <div class="filepath" id="fpath"></div>
  <div class="actions" id="acts">
    <button onclick="copyT()">Copy</button>
    <button onclick="dlMd()">Download .md</button>
  </div>
  <pre class="transcript" id="out"></pre>
</div>

<div class="card">
  <h2>Batch (one URL per line)</h2>
  <div class="row">
    <textarea id="burls" rows="3" style="flex:1;padding:.6rem;border-radius:7px;border:1px solid #ccc;
              font-size:.9rem;resize:vertical;" placeholder="Paste URLs, one per line..."></textarea>
    <button id="bgo" onclick="batch()" style="align-self:flex-start;">Go</button>
  </div>
  <div class="msg" id="bmsg"></div>
  <ul class="batch-list" id="blist"></ul>
</div>

<script>
const $=id=>document.getElementById(id);
let _title='', _text='';

async function extract() {
  const url=$('url').value.trim();
  if(!url) return;
  $('go').disabled=true;
  $('msg').className='msg'; $('msg').textContent='Extracting...';
  $('out').style.display='none'; $('acts').style.display='none'; $('fpath').style.display='none';
  try {
    const r=await fetch('/transcript',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({url,mode:$('mode').value})});
    if(!r.ok){const e=await r.json();throw new Error(e.detail||r.statusText);}
    const d=await r.json();
    _title=d.title; _text=d.transcript;
    $('msg').textContent='Done';
    $('fpath').textContent=d.filename; $('fpath').style.display='block';
    $('out').textContent=d.transcript; $('out').style.display='block';
    $('acts').style.display='flex';
  } catch(e) {
    $('msg').className='msg err'; $('msg').textContent=e.message;
  } finally { $('go').disabled=false; }
}

function copyT() {
  navigator.clipboard.writeText($('out').textContent);
  const b=event.target; b.textContent='Copied!'; setTimeout(()=>b.textContent='Copy',1200);
}

function dlMd() {
  const hdr=`# ${_title}\\n\\n---\\n\\n`;
  const blob=new Blob([hdr+_text],{type:'text/markdown'});
  const a=document.createElement('a');
  a.href=URL.createObjectURL(blob); a.download=(_title||'transcript')+'.md'; a.click();
}

async function batch() {
  const urls=$('burls').value.trim().split('\\n').map(u=>u.trim()).filter(Boolean);
  if(!urls.length) return;
  $('bgo').disabled=true;
  $('bmsg').className='msg'; $('bmsg').textContent='Submitting '+urls.length+' URLs...';
  $('blist').innerHTML='';
  try {
    const r=await fetch('/job',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({urls,mode:$('mode').value})});
    if(!r.ok){const e=await r.json();throw new Error(e.detail||r.statusText);}
    const d=await r.json();
    $('bmsg').textContent='Processing... (0/'+d.total+')';
    const poll=setInterval(async()=>{
      const pr=await fetch('/job/'+d.job_id);
      if(!pr.ok) return;
      const pd=await pr.json();
      $('bmsg').textContent=pd.status==='complete'
        ? 'Done ('+pd.completed+'/'+pd.total+')'
        : 'Processing... ('+pd.completed+'/'+pd.total+')';
      $('blist').innerHTML='';
      pd.results.forEach(r=>{
        const li=document.createElement('li');
        if(r.error){li.className='fail';li.textContent=r.url+' - '+r.error;}
        else{li.className='ok';li.textContent=r.title+' -> '+r.filename;}
        $('blist').appendChild(li);
      });
      if(pd.status==='complete'){clearInterval(poll);$('bgo').disabled=false;}
    },2000);
  } catch(e) {
    $('bmsg').className='msg err'; $('bmsg').textContent=e.message; $('bgo').disabled=false;
  }
}

$('url').addEventListener('keydown',e=>{if(e.key==='Enter')extract();});
</script>
</body>
</html>"""


if __name__ == "__main__":
    uvicorn.run(app, host=HOST, port=PORT, workers=1, log_level="info")
