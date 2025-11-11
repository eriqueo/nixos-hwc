#!/usr/bin/env python3
import argparse, json, os, re, sys, time
from datetime import datetime
from pathlib import Path
import requests

FILLER_PAT = re.compile(r"\b(?:um+|uh+|ah+|er+|hmm+|you know|like|sort of|kind of|i mean|well,|so,|basically|literally|right\?|okay|ok)\b", re.IGNORECASE)
MULTISPACE_PAT = re.compile(r"[ \t]{2,}")
TRAILING_SPACE_PAT = re.compile(r"[ \t]+$", re.MULTILINE)
FENCE_PAT = re.compile(r"(^```[\s\S]*?^```)", re.MULTILINE)

SYSTEM_PROMPT = "You are a meticulous technical writer. Rewrite the USER transcript into clean Markdown with a clear structure:\n- Add logical H1/H2/H3 headings.\n- Use concise paragraphs, bullet/numbered lists where helpful.\n- Bold important technical terms the speaker actually used.\n- Preserve code blocks and commands verbatim; never invent code.\n- Do not add new facts. If something is unclear, keep it terse and neutral.\n- Remove chit-chat and filler; keep only the instructional/technical essence.\n- Keep URLs and paths unchanged.\n- Use American English, consistent terminology, and parallel list structure.\nOutput valid Markdown only, no preamble or commentary."
CHUNK_USER_INSTRUCTION = "Restructure this transcript chunk. Keep ALL real technical content."
MERGE_USER_INSTRUCTION = "You will receive multiple already-structured Markdown chunks from the same transcript. Merge them into a single cohesive Markdown document:\n- Keep existing headings where appropriate; adjust levels for a consistent outline.\n- Remove duplicates and repeated intros/outros.\n- Ensure section ordering is logical and non-repetitive.\n- Do not add new content.\nOutput final Markdown only."

def strip_filler(text: str) -> str:
    fences = []
    def _stash(m):
        fences.append(m.group(1))
        return f"@@FENCE{len(fences)-1}@@"
    masked = FENCE_PAT.sub(_stash, text)
    masked = FILLER_PAT.sub("", masked)
    masked = MULTISPACE_PAT.sub(" ", masked)
    masked = TRAILING_SPACE_PAT.sub("", masked)
    lines = masked.splitlines()
    out_lines = []
    for ln in lines:
        if not ln.strip():
            out_lines.append(ln); continue
        if ln.lstrip().startswith(("-", "*", ">", "```", "    ", "\t")):
            out_lines.append(ln); continue
        stripped = ln.strip()
        if stripped and re.match(r"[a-z]", stripped[0]):
            stripped = stripped[0].upper() + stripped[1:]
        if re.search(r"[A-Za-z0-9)]$", stripped):
            stripped += "."
        leading = len(ln) - len(ln.lstrip(" "))
        out_lines.append(" " * leading + stripped)
    masked = "\n".join(out_lines)
    def _unstash(m):
        idx = int(m.group(0)[8:-2])
        return fences[idx]
    return re.sub(r"@@FENCE(\d+)@@", _unstash, masked).strip()

def split_on_paragraphs(text: str, target_chars: int = 12000, hard_cap: int = 16000) -> list:
    parts, buf, paras = [], [], text.split("\n\n")
    total = 0
    for para in paras:
        chunk_candidate = ("\n\n".join(buf + [para])).strip()
        if len(chunk_candidate) <= target_chars:
            buf.append(para); total = len(chunk_candidate)
        else:
            if buf:
                parts.append("\n\n".join(buf).strip())
                buf = [para]; total = len(para)
            else:
                s = para
                while len(s) > hard_cap:
                    parts.append(s[:hard_cap]); s = s[hard_cap:]
                buf = [s]; total = len(s)
    if buf: parts.append("\n\n".join(buf).strip())
    return parts if parts else [text]

def ollama_chat(model: str, system: str, user: str, host: str, temperature: float, top_p: float, retries: int = 3, timeout: float = 60.0) -> str:
    url = host.rstrip("/") + "/api/chat"
    payload = {"model": model, "messages": [{"role":"system","content":system},{"role":"user","content":user}], "options":{"temperature":temperature,"top_p":top_p}, "stream": False}
    backoff = 1.0; last = None
    for _ in range(retries):
        try:
            r = requests.post(url, json=payload, timeout=timeout)
            r.raise_for_status()
            data = r.json()
            return data.get("message", {}).get("content", "")
        except Exception as e:
            last = e; time.sleep(backoff); backoff = min(backoff*2, 8.0)
    raise RuntimeError(f"Ollama chat failed: {last}")

def process_file(src: Path, dst_dir: Path, model: str, host: str, temperature: float, top_p: float, force: bool) -> Path:
    dst = dst_dir / src.name
    meta = dst.with_suffix(".json")
    if dst.exists() and not force:
        return dst
    raw = src.read_text(encoding="utf-8", errors="ignore")
    cleaned = strip_filler(raw)
    chunks = split_on_paragraphs(cleaned)
    structured_chunks = []
    for ch in chunks:
        user_msg = CHUNK_USER_INSTRUCTION + "\n\n" + ch
        out = ollama_chat(model=model, system=SYSTEM_PROMPT, user=user_msg, host=host, temperature=temperature, top_p=top_p)
        structured_chunks.append(out.strip())
    if len(structured_chunks) == 1:
        final_md = structured_chunks[0]
    else:
        merged_input = "\n\n---\n\n".join(structured_chunks)
        final_md = ollama_chat(model=model, system=SYSTEM_PROMPT, user=MERGE_USER_INSTRUCTION + "\n\n" + merged_input, host=host, temperature=temperature, top_p=top_p)
    dst.write_text(final_md.strip() + "\n", encoding="utf-8")
    metadata = {"source": str(src), "output": str(dst), "model": model, "host": host, "temperature": temperature, "top_p": top_p, "chunks": len(chunks), "timestamp": datetime.utcnow().isoformat() + "Z"}
    meta.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    return dst

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", "-i", default=os.environ.get("TRANSCRIPTS_INPUT", "input_transcripts"))
    ap.add_argument("--output", "-o", default=os.environ.get("TRANSCRIPTS_OUTPUT", "cleaned_transcripts"))
    ap.add_argument("--pattern", "-p", default="*.md")
    ap.add_argument("--model", "-m", default=os.environ.get("OLLAMA_MODEL", "llama3"))
    ap.add_argument("--host", default=os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434"))
    ap.add_argument("--force", "-f", action="store_true")
    ap.add_argument("--temperature", type=float, default=float(os.environ.get("OLLAMA_TEMPERATURE", "0.2")))
    ap.add_argument("--top_p", type=float, default=float(os.environ.get("OLLAMA_TOP_P", "0.9")))
    args = ap.parse_args()
    in_dir = Path(args.input); out_dir = Path(args.output); out_dir.mkdir(parents=True, exist_ok=True)
    files = sorted(in_dir.glob(args.pattern))
    if not files:
        print(f"No files matching {args.pattern} in {in_dir}", file=sys.stderr); sys.exit(1)
    errors = 0
    for path in files:
        try:
            process_file(path, out_dir, args.model, args.host, args.temperature, args.top_p, args.force)
        except Exception as e:
            errors += 1; print(f"[ERROR] {path.name}: {e}", file=sys.stderr)
    sys.exit(1 if errors else 0)

if __name__ == "__main__":
    main()
