#!/usr/bin/env -S deno run --allow-read --allow-write --allow-net --allow-run --allow-env
/**
 * brain-mcp/parts/server.ts
 *
 * MCP server exposing the brain vault as filesystem + refactoring tools via
 * Streamable HTTP transport. Read/capture: read_note, write_note, list_notes,
 * search_notes, lint_wiki, append_to_inbox, inbox_capture. Semantic (brainvec
 * index + llama-embed): search_semantic, related_notes. Refactoring (git-
 * checkpointed): delete_note, move_note, replace_in_notes, update_frontmatter,
 * commit_vault.
 * Protocol: JSON-RPC 2.0 over HTTP POST (MCP spec 2024-11-05).
 * Auth: Bearer token read from BRAIN_MCP_KEY_FILE at startup.
 */

import { join, resolve, relative, dirname } from "jsr:@std/path@1";
import { walk, exists } from "jsr:@std/fs@1";

// ── Configuration ────────────────────────────────────────────────────────────
const VAULT_ROOT = resolve(Deno.env.get("BRAIN_VAULT_ROOT") ?? "/home/eric/900_vaults/brain");
const PORT = parseInt(Deno.env.get("BRAIN_MCP_PORT") ?? "9876");
const HOST = Deno.env.get("BRAIN_MCP_HOST") ?? "0.0.0.0";
const KEY_FILE = Deno.env.get("BRAIN_MCP_KEY_FILE") ?? "/run/agenix/brain-mcp-api-key";
// Semantic search: the brainvec index (built by brainvec-ingest.timer) + the
// local llama-embed backend for query-time embedding. Both optional — the
// tools degrade to actionable messages when either is absent.
const BRAINVEC_INDEX = Deno.env.get("BRAINVEC_INDEX") ?? "/home/eric/.cache/brainvec/index.jsonl";
const EMBED_BASE_URL = Deno.env.get("BRAINVEC_EMBED_BASE_URL") ?? "http://127.0.0.1:11502/v1";
const EMBED_MODEL = Deno.env.get("BRAINVEC_EMBED_MODEL") ?? "nomic-embed-text-v1.5";
const EMBED_PREFIX_QUERY = Deno.env.get("BRAINVEC_EMBED_PREFIX_QUERY") ?? "search_query: ";

let API_KEY: string;
try {
  API_KEY = (await Deno.readTextFile(KEY_FILE)).trim();
} catch (e) {
  console.error(`[brain-mcp] Cannot read API key from ${KEY_FILE}: ${e}`);
  Deno.exit(1);
}

// ── Path safety ──────────────────────────────────────────────────────────────
function safePath(rel: string): string {
  const normalized = resolve(join(VAULT_ROOT, rel));
  if (!normalized.startsWith(VAULT_ROOT + "/") && normalized !== VAULT_ROOT) {
    throw new Error(`Path traversal attempt blocked: ${rel}`);
  }
  return normalized;
}

// ── Walk skip set (shared by all vault scans) ─────────────────────────────────
// Excludes Syncthing version-history (.stversions), trash, git internals, and
// machine-local tooling dirs so link scans/rewrites never touch non-canonical
// copies (which would corrupt rewrites and produce false basename collisions).
const WALK_SKIP = [
  /\/\.obsidian\//, /\/\.git\//, /\/\.trash\//,
  /\/\.stversions\//, /\/\.brain\//, /\/\.claude\//,
];

function noteBasename(p: string): string {
  return p.replace(/.*\//, "").replace(/\.md$/, "");
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// ── Wikilink parsing/rewriting (shared by delete_note + move_note) ─────────────
// One definition of "what counts as a link target" so the two tools can't drift.
// Target = substring before the first '#' or '|' inside [[ ... ]].
// Handles [[x]], [[x|alias]], [[x#heading]], [[x#^block]], [[x#h|alias]], ![[x]].
type WikiLink = { full: string; target: string };

function parseWikilinks(text: string): WikiLink[] {
  const out: WikiLink[] = [];
  for (const m of text.matchAll(/\[\[([^\[\]]+?)\]\]/g)) {
    const target = m[1].split(/[#|]/)[0].trim();
    out.push({ full: m[0], target });
  }
  return out;
}

// Rewrite every [[oldBase...]] → [[newBase...]], preserving #heading/^block/|alias
// tails. Exact-token match (target === oldBase) so [[api]] never touches [[api-v2]].
function rewriteLinks(content: string, oldBase: string, newBase: string): { content: string; count: number } {
  let count = 0;
  const out = content.replace(/\[\[([^\[\]]+?)\]\]/g, (full, inner: string) => {
    const sep = inner.search(/[#|]/);
    const target = (sep === -1 ? inner : inner.slice(0, sep)).trim();
    const rest = sep === -1 ? "" : inner.slice(sep);
    if (target === oldBase) {
      count++;
      return `[[${newBase}${rest}]]`;
    }
    return full;
  });
  return { content: out, count };
}

// ── Vault scans ───────────────────────────────────────────────────────────────
type LinkHit = { file: string; line: number; text: string };

// Inbound [[basename]] links across the vault (used by delete_note's refusal
// check; move_note rewrites via the same parser so the two cannot disagree).
async function scanInboundLinks(basename: string, excludeFull?: string): Promise<LinkHit[]> {
  const hits: LinkHit[] = [];
  for await (const entry of walk(VAULT_ROOT, { exts: [".md"], skip: WALK_SKIP, includeDirs: false })) {
    if (excludeFull && entry.path === excludeFull) continue;
    const content = await Deno.readTextFile(entry.path);
    const lines = content.split("\n");
    for (let i = 0; i < lines.length; i++) {
      for (const link of parseWikilinks(lines[i])) {
        if (link.target === basename) {
          hits.push({ file: relative(VAULT_ROOT, entry.path), line: i + 1, text: lines[i].trim() });
          break;
        }
      }
    }
  }
  return hits;
}

// First note (other than excludeFull) whose basename equals `basename`, or null.
async function findBasenameOwner(basename: string, excludeFull?: string): Promise<string | null> {
  for await (const entry of walk(VAULT_ROOT, { exts: [".md"], skip: WALK_SKIP, includeDirs: false })) {
    if (excludeFull && entry.path === excludeFull) continue;
    if (noteBasename(entry.path) === basename) return relative(VAULT_ROOT, entry.path);
  }
  return null;
}

// Raw vault-relative path-string mentions of `relPath` (reported, never edited —
// historical/superseded notes intentionally preserve old paths).
async function scanPathMentions(relPath: string, excludeFull?: string): Promise<LinkHit[]> {
  const hits: LinkHit[] = [];
  for await (const entry of walk(VAULT_ROOT, { exts: [".md"], skip: WALK_SKIP, includeDirs: false })) {
    if (excludeFull && entry.path === excludeFull) continue;
    const content = await Deno.readTextFile(entry.path);
    const lines = content.split("\n");
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].includes(relPath)) {
        hits.push({ file: relative(VAULT_ROOT, entry.path), line: i + 1, text: lines[i].trim() });
      }
    }
  }
  return hits;
}

// ── Frontmatter ───────────────────────────────────────────────────────────────
// Set/replace a single key in the leading --- block without touching the body.
function setFrontmatterKey(content: string, key: string, value: string): string {
  const fm = content.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
  const line = `${key}: ${value}`;
  if (!fm) return `---\n${line}\n---\n\n${content}`;
  const block = fm[1];
  const keyRe = new RegExp(`^${escapeRegExp(key)}:.*$`, "m");
  const newBlock = keyRe.test(block) ? block.replace(keyRe, line) : `${block}\n${line}`;
  return content.replace(fm[0], `---\n${newBlock}\n---\n`);
}

// ── Git safety substrate ──────────────────────────────────────────────────────
// Every mutating tool brackets its change with git commits so any refactor is
// reversible. Tool commits are prefixed "brain-mcp:" so they stay greppable and
// distinct from human/Syncthing commits. Commits are LOCAL ONLY — never pushed.
const COMMIT_PREFIX = "brain-mcp";

// Shared lock with the vault-sync timer (domains/automation/vault-sync), which
// flocks this same file around its commit/pull/push. Serializing all git access
// through it means brain-mcp's checkpoints and the timer can never collide on
// .git/index.lock. Lives inside .git (git-ignored, Syncthing-ignored, local).
const GIT_LOCK = join(VAULT_ROOT, ".git", ".sync.lock");

async function git(gitArgs: string[]): Promise<{ code: number; stdout: string; stderr: string }> {
  // flock(1) blocks until the lock is free, then runs git holding it. Fall back
  // to a direct git call only when .git does not exist yet (first-run init),
  // since the lock path lives inside .git.
  const useLock = await exists(GIT_LOCK.replace(/\/\.sync\.lock$/, ""));
  const cmd = useLock
    ? new Deno.Command("flock", { args: [GIT_LOCK, "git", ...gitArgs], cwd: VAULT_ROOT, stdout: "piped", stderr: "piped" })
    : new Deno.Command("git", { args: gitArgs, cwd: VAULT_ROOT, stdout: "piped", stderr: "piped" });
  const { code, stdout, stderr } = await cmd.output();
  return { code, stdout: new TextDecoder().decode(stdout), stderr: new TextDecoder().decode(stderr) };
}

async function ensureGitRepo(): Promise<void> {
  if (await exists(join(VAULT_ROOT, ".git"))) return;
  await git(["init", "-b", "main"]);
  await git(["config", "user.name", "brain-mcp"]);
  await git(["config", "user.email", "brain-mcp@heartwoodcraft.me"]);
}

// Commit any pending vault state under a prefixed message. No-op if tree is clean.
async function gitCheckpoint(label: string): Promise<{ committed: boolean; hash: string | null }> {
  await ensureGitRepo();
  await git(["add", "-A"]);
  const staged = await git(["diff", "--cached", "--quiet"]);
  if (staged.code === 0) return { committed: false, hash: null }; // nothing staged
  const res = await git(["commit", "-m", `${COMMIT_PREFIX}: ${label}`]);
  if (res.code !== 0) throw new Error(`git commit failed: ${res.stderr || res.stdout}`);
  const hash = (await git(["rev-parse", "--short", "HEAD"])).stdout.trim();
  return { committed: true, hash };
}

// Atomic mutation bracket: snapshot pre-state, run fn, commit the result as one
// commit. On ANY error, hard-reset to the pre-state snapshot so a partial
// mutation (e.g. file moved but links half-rewritten) is fully rolled back —
// the operation is all-or-nothing and a single `git revert` undoes a success.
async function withCheckpoint<T>(
  label: string,
  fn: () => Promise<T>,
): Promise<{ result: T; commit: { committed: boolean; hash: string | null } }> {
  await gitCheckpoint(`checkpoint before ${label}`);
  try {
    const result = await fn();
    const commit = await gitCheckpoint(label);
    return { result, commit };
  } catch (e) {
    // Roll back tracked changes to the pre-mutation snapshot. We deliberately
    // do NOT `git clean -fd` here: that would delete ALL untracked files in the
    // vault (handoffs, _llm-inbox captures, run outputs, the embedded raw-import
    // repos) on any failure — the exact silent-data-loss footgun this migration
    // exists to kill. Tracked state is fully restored by reset; at worst a
    // failed move_note leaves a stray (untracked) destination file, which is
    // visible and recoverable rather than catastrophic.
    await git(["reset", "--hard", "HEAD"]);
    throw e;
  }
}

// ── Semantic index (brainvec) ────────────────────────────────────────────────
// Lazy, mtime-cached load of the brainvec JSONL index. cosine/topK are a
// deliberate ~15-line port of brainvec/lib.mjs (separate repo, node — a Deno
// import would couple deployments; duplication accepted and noted there).
interface VecEntry {
  path: string;
  title: string | null;
  type: string | null;
  embedId: string;
  vector: number[];
}
let vecCache: { mtime: number; entries: VecEntry[] } | null = null;

async function loadVecIndex(): Promise<VecEntry[] | null> {
  let stat;
  try {
    stat = await Deno.stat(BRAINVEC_INDEX);
  } catch {
    return null;
  }
  const mtime = stat.mtime?.getTime() ?? 0;
  if (vecCache && vecCache.mtime === mtime) return vecCache.entries;
  const entries: VecEntry[] = [];
  for (const line of (await Deno.readTextFile(BRAINVEC_INDEX)).split("\n")) {
    if (!line.trim()) continue;
    try {
      entries.push(JSON.parse(line));
    } catch { /* skip corrupt line */ }
  }
  vecCache = { mtime, entries };
  return entries;
}

function cosine(a: number[], b: number[]): number {
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return dot / (Math.sqrt(na) * Math.sqrt(nb) || 1);
}

function vecTopK(queryVec: number[], entries: VecEntry[], k: number) {
  return entries
    .map((e) => ({ path: e.path, title: e.title, type: e.type, score: cosine(queryVec, e.vector) }))
    .sort((a, b) => b.score - a.score)
    .slice(0, k);
}

async function embedQuery(text: string): Promise<number[]> {
  const res = await fetch(`${EMBED_BASE_URL}/embeddings`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ model: EMBED_MODEL, input: [EMBED_PREFIX_QUERY + text.slice(0, 2000)] }),
    signal: AbortSignal.timeout(20_000),
  });
  const data = await res.json().catch(() => null);
  const vec = data?.data?.[0]?.embedding;
  if (!res.ok || !vec) throw new Error(`embed backend ${res.status}`);
  return vec;
}

function formatHits(hits: Array<{ path: string; title: string | null; type: string | null; score: number }>): string {
  if (!hits.length) return "No semantic matches.";
  return hits
    .map((h, i) => `${String(i + 1).padStart(2)}. ${h.score.toFixed(4)}  ${h.path}${h.title ? `  — ${h.title}` : ""}${h.type ? `  [${h.type}]` : ""}`)
    .join("\n") + "\n(scores are cosine similarity ∈ [-1,1]; treat hits as leads, verify content)";
}

// ── MCP tool definitions ─────────────────────────────────────────────────────
const TOOL_DEFS = [
  {
    name: "read_note",
    description: "Read a note from the brain vault by relative path",
    inputSchema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Path relative to vault root (e.g. wiki/foo.md)" }
      },
      required: ["path"]
    }
  },
  {
    name: "write_note",
    description: "Create or overwrite a note in the brain vault",
    inputSchema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Path relative to vault root" },
        content: { type: "string", description: "Full file content to write" }
      },
      required: ["path", "content"]
    }
  },
  {
    name: "list_notes",
    description: "List .md files in a vault folder (recursive)",
    inputSchema: {
      type: "object",
      properties: {
        folder: { type: "string", description: "Folder relative to vault root. Omit to list all notes." }
      }
    }
  },
  {
    name: "search_notes",
    description: "Full-text search across vault notes using ripgrep",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "Search query (ripgrep regex)" },
        folder: { type: "string", description: "Optional subfolder to limit search scope" }
      },
      required: ["query"]
    }
  },
  {
    name: "search_semantic",
    description: "Semantic (meaning-based) search over the vault's brainvec embedding index. Use for concept/topic queries; complements search_notes (keyword/regex, better for exact strings and identifiers).",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "Natural-language query" },
        k: { type: "number", description: "Max results (default 10)" },
        folder: { type: "string", description: "Optional vault-relative folder prefix filter (e.g. datax/wiki)" }
      },
      required: ["query"]
    }
  },
  {
    name: "related_notes",
    description: "Notes semantically nearest to an existing note (link discovery, fold-target matching). Uses the note's stored vector — no embedding backend needed.",
    inputSchema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Vault-relative note path (e.g. tech/wiki/nixos/secrets.md)" },
        k: { type: "number", description: "Max results (default 10)" }
      },
      required: ["path"]
    }
  },
  {
    name: "lint_wiki",
    description: "Check wiki health: orphan pages, broken [[wikilinks]], frontmatter issues",
    inputSchema: {
      type: "object",
      properties: {}
    }
  },
  {
    name: "append_to_inbox",
    description: "Write a fleeting note to inbox/ for later processing",
    inputSchema: {
      type: "object",
      properties: {
        content: { type: "string", description: "Note content to save" },
        filename: { type: "string", description: "Filename (auto-generated timestamp if omitted)" }
      },
      required: ["content"]
    }
  },
  {
    name: "inbox_capture",
    description: "Persist an LLM-derived insight to _llm-inbox/<YYYY-MM-DD>/<HHMMSS>-<slug>.md with frontmatter. Use this for chunks/summaries/notes generated by an agent — _llm-inbox/ is separate from inbox/ (human captures) and sorts to the top of the file listing so review is explicit.",
    inputSchema: {
      type: "object",
      properties: {
        content: { type: "string", description: "Markdown body of the note" },
        source: { type: "string", description: "Where this came from (e.g. 'persona-daemon:assistant', 'hermes:summarizer')" },
        conversation_id: { type: "string", description: "Optional uuid of the conversation that produced this insight" },
        tags: { type: "array", items: { type: "string" }, description: "Optional tags to add to frontmatter" }
      },
      required: ["content", "source"]
    }
  },
  {
    name: "delete_note",
    description: "Hard-delete a note from the vault. Refuses if other notes link to it ([[basename]]) unless force=true, to avoid silently creating dangling links. Commits a git checkpoint before deleting (reversible via git).",
    inputSchema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Path relative to vault root (e.g. wiki/datax/foo.md)" },
        force: { type: "boolean", description: "Delete even if inbound [[wikilinks]] exist (default false)" }
      },
      required: ["path"]
    }
  },
  {
    name: "move_note",
    description: "Move/rename a note within the vault. When update_links is true (default), rewrites every inbound [[wikilink]] form ([[x]], [[x|alias]], [[x#heading]], [[x#^block]]) across the vault to the new basename. Refuses if the destination basename already exists elsewhere (Obsidian resolves links by basename). Reports — but does not edit — raw path-string mentions of the old path. The entire operation is one atomic git commit.",
    inputSchema: {
      type: "object",
      properties: {
        from: { type: "string", description: "Current path relative to vault root" },
        to: { type: "string", description: "Destination path relative to vault root" },
        update_links: { type: "boolean", description: "Rewrite inbound wikilinks to the new basename (default true)" }
      },
      required: ["from", "to"]
    }
  },
  {
    name: "replace_in_notes",
    description: "Bulk find/replace across vault notes, optionally scoped to a folder. dry_run (default true) returns the would-change matches with file+line context and changes nothing; dry_run=false applies and commits a git checkpoint. Set regex=true to treat pattern as a JS regular expression (replacement may use $1 backrefs).",
    inputSchema: {
      type: "object",
      properties: {
        pattern: { type: "string", description: "Text or regex to find" },
        replacement: { type: "string", description: "Replacement text" },
        folder: { type: "string", description: "Optional subfolder to scope the operation" },
        regex: { type: "boolean", description: "Treat pattern as a regular expression (default false = literal)" },
        dry_run: { type: "boolean", description: "Preview only; change nothing (default true)" }
      },
      required: ["pattern", "replacement"]
    }
  },
  {
    name: "update_frontmatter",
    description: "Set or replace a single YAML frontmatter field on a note without rewriting the body. Adds a frontmatter block if none exists. Commits a git checkpoint.",
    inputSchema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Path relative to vault root" },
        key: { type: "string", description: "Frontmatter key to set (e.g. status, tags)" },
        value: { type: "string", description: "Value to assign (written verbatim after 'key: ')" }
      },
      required: ["path", "key", "value"]
    }
  },
  {
    name: "commit_vault",
    description: "Commit the current vault state as an explicit git checkpoint (prefixed 'brain-mcp:'). No-op if the working tree is clean. Use for manual rollback points mid-refactor.",
    inputSchema: {
      type: "object",
      properties: {
        message: { type: "string", description: "Commit message (prefixed with 'brain-mcp:')" }
      }
    }
  }
];

// ── Tool implementations ──────────────────────────────────────────────────────
type ToolArgs = Record<string, unknown>;
type ToolResult = { content: Array<{ type: string; text: string }> };

async function callTool(name: string, args: ToolArgs): Promise<ToolResult> {
  switch (name) {
    case "read_note": {
      const path = String(args.path);
      const full = safePath(path);
      const text = await Deno.readTextFile(full);
      return { content: [{ type: "text", text }] };
    }

    case "write_note": {
      const path = String(args.path);
      const content = String(args.content);
      const full = safePath(path);
      await Deno.mkdir(dirname(full), { recursive: true });
      await Deno.writeTextFile(full, content);
      return { content: [{ type: "text", text: `Written: ${path} (${content.length} bytes)` }] };
    }

    case "list_notes": {
      const folder = args.folder ? String(args.folder) : undefined;
      const dir = folder ? safePath(folder) : VAULT_ROOT;
      const files: string[] = [];
      for await (const entry of walk(dir, {
        exts: [".md"],
        skip: [/\/.obsidian\//, /\/.git\//, /\/.trash\//],
        includeDirs: false,
      })) {
        files.push(relative(VAULT_ROOT, entry.path));
      }
      files.sort();
      return { content: [{ type: "text", text: files.length > 0 ? files.join("\n") : "(empty)" }] };
    }

    case "search_notes": {
      const query = String(args.query);
      const folder = args.folder ? String(args.folder) : undefined;
      const searchDir = folder ? safePath(folder) : VAULT_ROOT;

      const cmd = new Deno.Command("rg", {
        args: ["--with-filename", "--line-number", "--color", "never", query, searchDir],
        stdout: "piped",
        stderr: "piped",
      });
      const { stdout } = await cmd.output();
      const raw = new TextDecoder().decode(stdout);
      // Make paths relative to vault root for cleaner output
      const output = raw.replaceAll(VAULT_ROOT + "/", "");
      return { content: [{ type: "text", text: output || "No matches found." }] };
    }

    case "search_semantic": {
      const entries = await loadVecIndex();
      if (!entries || !entries.length) {
        return { content: [{ type: "text", text: `Semantic index not found/empty at ${BRAINVEC_INDEX} — run brainvec-ingest on the server (systemctl start brainvec-ingest), or use search_notes (keyword) instead.` }] };
      }
      // Model-drift guard: mixed-model cosine is garbage; be loud about it.
      const foreign = entries.filter((e) => !e.embedId?.startsWith(EMBED_MODEL)).length;
      if (foreign > entries.length / 2) {
        return { content: [{ type: "text", text: `Semantic index was built with a different embedding model (${entries[0]?.embedId}) than this server queries with (${EMBED_MODEL}) — re-run ingest with --force. Use search_notes meanwhile.` }] };
      }
      let queryVec: number[];
      try {
        queryVec = await embedQuery(String(args.query));
      } catch {
        return { content: [{ type: "text", text: `Embedding backend down (${EMBED_BASE_URL}, llama-embed) — semantic search unavailable; use search_notes (keyword) instead.` }] };
      }
      const k = args.k ? Number(args.k) : 10;
      const folder = args.folder ? String(args.folder).replace(/\/$/, "") + "/" : null;
      const pool = folder ? entries.filter((e) => e.path.startsWith(folder)) : entries;
      return { content: [{ type: "text", text: formatHits(vecTopK(queryVec, pool, k)) }] };
    }

    case "related_notes": {
      const entries = await loadVecIndex();
      if (!entries || !entries.length) {
        return { content: [{ type: "text", text: `Semantic index not found/empty at ${BRAINVEC_INDEX} — run brainvec-ingest on the server first.` }] };
      }
      const rel = String(args.path).replace(/^\//, "");
      const self = entries.find((e) => e.path === rel) ?? entries.find((e) => e.path.endsWith(rel));
      if (!self) {
        return { content: [{ type: "text", text: `Note not in the semantic index: ${rel} (new/renamed since the last ingest tick? next *:5/15 run picks it up).` }] };
      }
      const k = args.k ? Number(args.k) : 10;
      const hits = vecTopK(self.vector, entries.filter((e) => e.path !== self.path), k);
      return { content: [{ type: "text", text: formatHits(hits) }] };
    }

    case "lint_wiki": {
      const wikiDir = join(VAULT_ROOT, "wiki");
      if (!await exists(wikiDir)) {
        return { content: [{ type: "text", text: "wiki/ directory not found or empty." }] };
      }

      const wikiFiles = new Map<string, string>(); // slug → full path
      const inbound = new Map<string, Set<string>>(); // slug → set of pages linking to it

      for await (const entry of walk(wikiDir, { exts: [".md"], includeDirs: false })) {
        const slug = entry.name.replace(/\.md$/, "");
        wikiFiles.set(slug, entry.path);
        inbound.set(slug, new Set());
      }

      const brokenLinks: string[] = [];
      const frontmatterIssues: string[] = [];

      for (const [slug, path] of wikiFiles) {
        const content = await Deno.readTextFile(path);

        if (!content.startsWith("---")) {
          frontmatterIssues.push(`${slug}: missing frontmatter`);
        }

        for (const m of content.matchAll(/\[\[([^\]|#]+)/g)) {
          const target = m[1].trim().replace(/\.md$/, "");
          if (wikiFiles.has(target)) {
            inbound.get(target)!.add(slug);
          } else {
            brokenLinks.push(`${slug} → [[${m[1].trim()}]]`);
          }
        }
      }

      const orphans = [...wikiFiles.keys()].filter(
        (slug) => !slug.startsWith("_") && (inbound.get(slug)?.size ?? 0) === 0
      );

      const report = [
        `# Wiki Lint Report — ${new Date().toISOString().slice(0, 10)}`,
        `\nTotal wiki pages: ${wikiFiles.size}`,
        `\n## Broken wikilinks (${brokenLinks.length})`,
        ...brokenLinks.map((l) => `- ${l}`),
        `\n## Orphan pages (${orphans.length})`,
        ...orphans.map((p) => `- ${p}`),
        `\n## Frontmatter issues (${frontmatterIssues.length})`,
        ...frontmatterIssues.map((i) => `- ${i}`),
      ].join("\n");

      return { content: [{ type: "text", text: report }] };
    }

    case "append_to_inbox": {
      const content = String(args.content);
      const ts = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
      const filename = args.filename ? String(args.filename) : `capture-${ts}.md`;
      const full = safePath(`inbox/${filename}`);
      await Deno.mkdir(dirname(full), { recursive: true });
      await Deno.writeTextFile(full, content);
      return { content: [{ type: "text", text: `Saved: inbox/${filename}` }] };
    }

    case "inbox_capture": {
      const content = String(args.content ?? "");
      const source = String(args.source ?? "unknown");
      const conversationId = args.conversation_id
        ? String(args.conversation_id) : null;
      const tags = Array.isArray(args.tags)
        ? args.tags.map(String) : [];
      if (!content) {
        throw new Error("inbox_capture: content is required and non-empty");
      }

      const now = new Date();
      const dateDir = now.toISOString().slice(0, 10);     // YYYY-MM-DD
      const timeSlug = now.toISOString().slice(11, 19).replace(/:/g, "");

      // Derive a kebab-case slug from the first heading or first 60 chars
      // of body. Strip frontmatter if the caller pre-embedded any.
      const stripFm = content.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, "");
      const firstH1 = stripFm.match(/^#\s+(.+)$/m);
      const seed = (firstH1 ? firstH1[1] : stripFm)
        .trim().slice(0, 60);
      const slug = seed
        .toLowerCase()
        .replace(/[^a-z0-9\s-]/g, "")
        .replace(/\s+/g, "-")
        .replace(/-+/g, "-")
        .replace(/^-|-$/g, "") || "note";

      const filename = `${timeSlug}-${slug}.md`;
      const rel = `_llm-inbox/${dateDir}/${filename}`;
      const full = safePath(rel);

      const fm: string[] = ["---"];
      fm.push(`title: ${seed.replace(/[\r\n]/g, " ") || "(untitled)"}`);
      fm.push(`created: ${now.toISOString()}`);
      fm.push(`updated: ${now.toISOString()}`);
      fm.push(`source: [${JSON.stringify(source)}]`);
      if (conversationId) fm.push(`conversation_id: ${conversationId}`);
      const allTags = ["_llm-inbox", ...tags];
      fm.push(`tags: [${allTags.map((t) => JSON.stringify(t)).join(", ")}]`);
      fm.push("status: needs-review");
      fm.push("---");
      fm.push("");

      const body = stripFm.trim() + "\n";
      const full_content = fm.join("\n") + body;

      await Deno.mkdir(dirname(full), { recursive: true });
      await Deno.writeTextFile(full, full_content);
      return {
        content: [{
          type: "text",
          text: `Saved: ${rel} (${full_content.length} bytes)`,
        }],
      };
    }

    case "delete_note": {
      const path = String(args.path);
      const force = args.force === true;
      const full = safePath(path);
      if (!await exists(full)) throw new Error(`Not found: ${path}`);
      if ((await Deno.stat(full)).isDirectory) {
        throw new Error(`Refusing to delete a directory: ${path}`);
      }
      const base = noteBasename(full);
      const inbound = await scanInboundLinks(base, full);
      if (inbound.length > 0 && !force) {
        const list = inbound.map((h) => `- ${h.file}:${h.line}  ${h.text}`).join("\n");
        return { content: [{ type: "text", text:
          `Refused: ${inbound.length} inbound [[${base}]] link(s) would dangle.\nPass force=true to delete anyway.\n\n${list}` }] };
      }
      const { commit } = await withCheckpoint(`delete_note ${path}`, async () => {
        await Deno.remove(full);
      });
      const warn = inbound.length > 0
        ? `\nWARNING: ${inbound.length} now-dangling [[${base}]] link(s) remain (forced).` : "";
      return { content: [{ type: "text", text:
        `Deleted: ${path}${commit.hash ? ` (commit ${commit.hash})` : ""}${warn}` }] };
    }

    case "move_note": {
      const from = String(args.from);
      const to = String(args.to);
      const updateLinks = args.update_links !== false;
      const fromFull = safePath(from);
      const toFull = safePath(to);
      if (!await exists(fromFull)) throw new Error(`Source not found: ${from}`);
      if (await exists(toFull)) throw new Error(`Destination already exists: ${to}`);
      const oldBase = noteBasename(fromFull);
      const newBase = noteBasename(toFull);
      if (newBase !== oldBase) {
        const owner = await findBasenameOwner(newBase, fromFull);
        if (owner) {
          throw new Error(
            `Basename collision: "${newBase}" already exists at ${owner}. ` +
            `Obsidian resolves links by basename — refusing to create a duplicate.`,
          );
        }
      }
      const rewritten: string[] = [];
      const { commit } = await withCheckpoint(`move_note ${from} -> ${to}`, async () => {
        await Deno.mkdir(dirname(toFull), { recursive: true });
        await Deno.rename(fromFull, toFull);
        if (updateLinks && newBase !== oldBase) {
          for await (const entry of walk(VAULT_ROOT, { exts: [".md"], skip: WALK_SKIP, includeDirs: false })) {
            const content = await Deno.readTextFile(entry.path);
            const { content: out, count } = rewriteLinks(content, oldBase, newBase);
            if (count > 0) {
              await Deno.writeTextFile(entry.path, out);
              rewritten.push(`${relative(VAULT_ROOT, entry.path)} (${count})`);
            }
          }
        }
      });
      const mentions = await scanPathMentions(from, toFull);
      const parts = [`Moved: ${from} → ${to}${commit.hash ? ` (commit ${commit.hash})` : ""}`];
      parts.push(`\nLinks rewritten in ${rewritten.length} file(s):`);
      parts.push(rewritten.length ? rewritten.map((r) => `- ${r}`).join("\n") : "- (none)");
      if (mentions.length) {
        parts.push(`\nRaw path-string mentions of "${from}" (NOT edited — review manually):`);
        parts.push(mentions.map((m) => `- ${m.file}:${m.line}  ${m.text}`).join("\n"));
      }
      return { content: [{ type: "text", text: parts.join("\n") }] };
    }

    case "replace_in_notes": {
      const pattern = String(args.pattern);
      const replacement = String(args.replacement ?? "");
      const folder = args.folder ? String(args.folder) : undefined;
      const useRegex = args.regex === true;
      const dryRun = args.dry_run !== false;
      const dir = folder ? safePath(folder) : VAULT_ROOT;
      const buildRe = () => new RegExp(useRegex ? pattern : escapeRegExp(pattern), "g");

      type FileChange = { file: string; full: string; hits: Array<{ line: number; before: string; after: string }> };
      const changes: FileChange[] = [];
      for await (const entry of walk(dir, { exts: [".md"], skip: WALK_SKIP, includeDirs: false })) {
        const content = await Deno.readTextFile(entry.path);
        const lines = content.split("\n");
        const hits: Array<{ line: number; before: string; after: string }> = [];
        for (let i = 0; i < lines.length; i++) {
          if (buildRe().test(lines[i])) {
            hits.push({ line: i + 1, before: lines[i], after: lines[i].replace(buildRe(), replacement) });
          }
        }
        if (hits.length) changes.push({ file: relative(VAULT_ROOT, entry.path), full: entry.path, hits });
      }

      const totalHits = changes.reduce((s, c) => s + c.hits.length, 0);
      const header = `${dryRun ? "[DRY RUN] " : ""}${useRegex ? `/${pattern}/` : JSON.stringify(pattern)}` +
        ` → ${JSON.stringify(replacement)}${folder ? ` in ${folder}/` : ""}\n` +
        `${totalHits} match(es) across ${changes.length} file(s)`;

      if (totalHits === 0) return { content: [{ type: "text", text: `${header}\n(no matches)` }] };

      const preview = changes.map((c) =>
        `\n## ${c.file}\n` + c.hits.map((h) => `  ${h.line}: - ${h.before}\n  ${h.line}: + ${h.after}`).join("\n")
      ).join("\n");

      if (dryRun) {
        return { content: [{ type: "text", text:
          `${header}\nRun again with dry_run=false to apply.\n${preview}` }] };
      }

      const label = `replace_in_notes ${useRegex ? `/${pattern}/` : JSON.stringify(pattern)}` +
        ` -> ${JSON.stringify(replacement)}${folder ? ` in ${folder}` : ""}`;
      const { commit } = await withCheckpoint(label, async () => {
        for (const c of changes) {
          const content = await Deno.readTextFile(c.full);
          await Deno.writeTextFile(c.full, content.replace(buildRe(), replacement));
        }
      });
      return { content: [{ type: "text", text:
        `${header}${commit.hash ? ` (commit ${commit.hash})` : ""}\nApplied.\n${preview}` }] };
    }

    case "update_frontmatter": {
      const path = String(args.path);
      const key = String(args.key);
      const value = String(args.value);
      const full = safePath(path);
      if (!await exists(full)) throw new Error(`Not found: ${path}`);
      const { commit } = await withCheckpoint(`update_frontmatter ${path} ${key}=${value}`, async () => {
        const content = await Deno.readTextFile(full);
        await Deno.writeTextFile(full, setFrontmatterKey(content, key, value));
      });
      return { content: [{ type: "text", text:
        `Set ${key}: ${value} in ${path}${commit.hash ? ` (commit ${commit.hash})` : ""}` }] };
    }

    case "commit_vault": {
      const message = String(args.message ?? "manual checkpoint");
      const cp = await gitCheckpoint(message);
      return { content: [{ type: "text", text:
        cp.committed ? `Committed ${cp.hash}: ${COMMIT_PREFIX}: ${message}` : "Nothing to commit (working tree clean)." }] };
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

// ── JSON-RPC protocol ─────────────────────────────────────────────────────────
type RpcReq = { jsonrpc: "2.0"; id?: string | number | null; method: string; params?: unknown };
type RpcResp = { jsonrpc: "2.0"; id: string | number | null; result?: unknown; error?: { code: number; message: string } };

function rpcError(id: string | number | null, code: number, message: string): RpcResp {
  return { jsonrpc: "2.0", id, error: { code, message } };
}

async function handleRpc(req: RpcReq): Promise<RpcResp | null> {
  const id = req.id ?? null;
  try {
    switch (req.method) {
      case "initialize":
        return {
          jsonrpc: "2.0", id,
          result: {
            protocolVersion: "2024-11-05",
            serverInfo: { name: "brain-mcp", version: "1.0.0" },
            capabilities: { tools: {} },
          },
        };

      case "notifications/initialized":
        return null; // notifications have no response

      case "ping":
        return { jsonrpc: "2.0", id, result: {} };

      case "tools/list":
        return { jsonrpc: "2.0", id, result: { tools: TOOL_DEFS } };

      case "tools/call": {
        const p = req.params as { name: string; arguments?: ToolArgs };
        const result = await callTool(p.name, p.arguments ?? {});
        return { jsonrpc: "2.0", id, result };
      }

      default:
        return rpcError(id, -32601, `Method not found: ${req.method}`);
    }
  } catch (e) {
    return rpcError(id, -32603, e instanceof Error ? e.message : String(e));
  }
}

// ── HTTP server ───────────────────────────────────────────────────────────────
Deno.serve({ port: PORT, hostname: HOST }, async (req: Request): Promise<Response> => {
  const url = new URL(req.url);

  // Health check — no auth required
  if (url.pathname === "/health" && req.method === "GET") {
    return Response.json({ status: "ok", service: "brain-mcp", vault: VAULT_ROOT, port: PORT });
  }

  // Auth: Cloudflare Access Managed OAuth at the network boundary.
  //   - Public URL: https://brain.heartwoodcraft.me/mcp
  //   - Managed OAuth toggle ON in the Cloudflare Access self-hosted app makes
  //     Access an RFC 8414 / RFC 9728-compliant OAuth 2.1 authorization server
  //     with Dynamic Client Registration (DCR) + PKCE.
  //   - claude.ai discovers it via the WWW-Authenticate / .well-known endpoints,
  //     registers dynamically, then sends a Bearer access token Cloudflare validates.
  //   - Cloudflare strips the Bearer (Access JWT) before forwarding here, so this
  //     process sees an authenticated request with no Authorization header to check.
  //   - Internal Tailscale path (http://server:9876/mcp) bypasses Cloudflare and is
  //     intentionally open; protected only by the Tailscale identity layer.
  //   - App-level Bearer check removed 2026-05-22 — Access is the sole gate.

  if (url.pathname === "/mcp" || url.pathname === "/mcp/") {
    if (req.method !== "POST") {
      return new Response("Method Not Allowed — use POST for MCP", { status: 405 });
    }

    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return Response.json(rpcError(null, -32700, "Parse error: invalid JSON"), { status: 400 });
    }

    if (Array.isArray(body)) {
      const results = (
        await Promise.all(body.map((r) => handleRpc(r as RpcReq)))
      ).filter((r): r is RpcResp => r !== null);
      return Response.json(results, { headers: { "Content-Type": "application/json" } });
    }

    const result = await handleRpc(body as RpcReq);
    if (result === null) return new Response(null, { status: 204 });
    return Response.json(result, { headers: { "Content-Type": "application/json" } });
  }

  return new Response("Not Found", { status: 404 });
});

console.log(`[brain-mcp] Listening on ${HOST}:${PORT} — vault: ${VAULT_ROOT}`);
