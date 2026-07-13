# persona-daemon

`hwc.server.ai.personaDaemon` — Deno HTTP daemon that wraps the three
llama-cpp services with persona resolution, conversation memory (SQLite),
and (in Commit 3) RAG over the brain vault.

Listens on `127.0.0.1:11550`. External access via Caddy name-based vhost
`persona-daemon.hwc.iheartwoodcraft.com` (was port `:28443`).

## Endpoints

| Route | Method | Purpose |
|---|---|---|
| `/v1/chat/completions` | POST | OpenAI-compatible + extras (`persona`, `conversation_id`, `new_conversation`, `use_knowledge`) |
| `/v1/models`           | GET  | Lists personas (so OpenAI clients can pick one without knowing the extension) |
| `/healthz`             | GET  | Liveness + uptime + persona count |
| `/_internal/health`    | GET  | Alias |
| `/_internal/conversations` | GET  | List conversations (`?persona=`, `?limit=`) |
| `/_internal/conversations` | POST | Create (`{persona, title?}` → `{id, persona}`) |

Coming in later commits: `POST /_internal/reindex` (Commit 3), `GET /metrics`
+ `/mcp` (Commit 4).

## Architecture

Hexagonal — `core/` knows nothing about HTTP, SQLite, or llama.cpp;
`adapters/` implement the ports defined in `ports/`; `shells/` translate
inbound and outbound. Composition root in `main.ts`.

```
parts/src/
├── core/
│   ├── chat.ts             # orchestrate(req) — single-turn flow
│   ├── prompt-envelope.ts  # pinned system-prompt contract
│   ├── summarization.ts    # placeholder (Commit 2); real summarize later
│   ├── errors.ts           # PersonaDaemonError + code enum + HTTP map
│   └── types.ts            # Zod schemas + domain types
├── ports/
│   ├── llm.ts              # ChatPort, EmbedPort
│   ├── store.ts            # ConversationStore (VectorStore in Commit 3)
│   ├── clock.ts
│   └── log.ts
├── adapters/
│   ├── llm-llamacpp.ts     # OpenAI-HTTP impls of ChatPort + EmbedPort
│   ├── store-sqlite.ts     # @db/sqlite + WAL + busy-retry impl
│   ├── clock-system.ts
│   └── log-stderr.ts       # structured JSON one-line-per-event
├── shells/
│   ├── http-openai.ts      # /v1/chat/completions + /v1/models
│   └── http-internal.ts    # /healthz + /_internal/*
├── main.ts                 # composition root (reads env, wires deps)
└── deno.jsonc              # pin npm:zod, jsr:@db/sqlite, jsr:@std/uuid
```

## Configuration (Charter: late binding via env vars)

All runtime knobs flow in through `PERSONA_DAEMON_*` env vars set by the
NixOS module. Nothing in core or adapters reads `Deno.env` — only
`main.ts` does, then hands frozen values into the wiring. This keeps the
TS code agnostic to its host and trivially testable.

Persona schema additions (consumed by the daemon, defined in
`domains/ai/personas/library/_defaults.nix`):

| Field | Type | Effect |
|---|---|---|
| `useMemory` | bool | Persist conversation turns; required for `--conversation` to work |
| `useKnowledge` | bool | (Commit 3) Embed query, inject top-K vault chunks |
| `knowledgeTopK` | int | How many chunks to retrieve when `useKnowledge=true` |

## Dev workflow

The TS source is bundled into the Nix store via `sourceFilesBySuffices`
(matching hermes). Iteration loop:

```bash
# edit .ts files under parts/src/
sudo nixos-rebuild switch --flake ~/.nixos#hwc-server
journalctl -u persona-daemon -f --no-pager
curl -s http://127.0.0.1:11550/healthz | jq
```

For ad-hoc testing without redeploying, you can run a one-off Deno
process pointing at the same llama-cpp services:

```bash
cd ~/.nixos/domains/server/native/ai/persona-daemon/parts/src
PERSONA_DAEMON_BIND_ADDR=127.0.0.1 \
PERSONA_DAEMON_PORT=11551 \
PERSONA_DAEMON_DB_PATH=/tmp/persona-dev.db \
PERSONA_DAEMON_MANIFEST=$(nix eval --raw .#nixosConfigurations.hwc-server.config.environment.etc."personas.json".source 2>/dev/null \
                          || find /nix/store -name 'hwc-personas.json' | head -1) \
PERSONA_DAEMON_GPU_URL=http://127.0.0.1:11500 \
PERSONA_DAEMON_CPU_URL=http://127.0.0.1:11501 \
PERSONA_DAEMON_EMBED_URL=http://127.0.0.1:11502 \
PERSONA_DAEMON_MAX_RECENT=16 PERSONA_DAEMON_KEEP_RECENT=8 \
PERSONA_DAEMON_LOG_LEVEL=debug \
deno task dev
```

## Failure modes (selected — full matrix in plan)

- **Chat backend down** → HTTP 503 `CHAT_BACKEND_UNAVAILABLE` with
  `{backend, endpoint}` detail. No silent fallback (persona pins model).
- **SQLite contention** → WAL mode + 5s busy timeout + one retry.
- **Persona unknown** → HTTP 404 `PERSONA_UNKNOWN` with `{available}` list.
- **Conversation overflow** → Commit 2: placeholder summary, log warn.
  Commit 3+: real background summarization via persona's own backend.

## Roadmap

- ✅ **Commit 2** — conversations only. `useMemory`-aware persistence.
- ✅ **Commit 3** — `VectorStore`, vault indexer, `useKnowledge`-aware RAG;
  `POST /_internal/reindex` + systemd path unit; `persona-admin reindex` CLI.
- ✅ **Commit 4** — MCP shell (HTTP at `/mcp`), Caddy route 28443,
  Prometheus `/metrics` + scrape + `PersonaDaemonReindexStale` /
  `PersonaDaemonBackendDown` alerts, vault writeback via brain-mcp's
  new `inbox_capture` tool.
- 🔭 **Later** — real conversation summarization (currently a truncation
  marker), MCP stdio shell for Hermes skill provider integration, ramp
  `knowledgeTopK` per-persona based on actual retrieval quality, optional
  reranker over the top 50 cosine candidates.

## Changelog

- 2026-06-09: Law 10 migration — `options.nix` inlined into `index.nix`'s
  `# OPTIONS` section (one of the 18 remaining stragglers from the v11.0 audit).
  Pure relocation, no semantic change; hwc-server toplevel drv hash unchanged.
- 2026-06-09: Caddy route migrated from port-mode `:28443` to name-based vhost `persona-daemon.hwc.iheartwoodcraft.com` (shared `*.hwc.iheartwoodcraft.com` wildcard cert, no firewall port). See `domains/networking/README.md`.
- 2026-06-02: vault path follows the move from `/mnt/vaults/brain` to
  `/home/eric/900_vaults/brain`. Only the `vaultPath` option's doc/default
  reference changed — the value is inherited from
  `hwc.paths.brain.server-replica`, so this is a default+doc sync, not a
  behavior change. The old path no longer exists on hwc-server.
- 2026-06-01: Add 5-min periodic reindex timer alongside the path unit.
  `systemd.path` `PathChanged=` only watches the directory's immediate
  entries — edits under `wiki/`, `_llm-inbox/`, etc. never fire the
  trigger, so the index drifted stale between service restarts. The
  timer covers subdirectory edits; the path unit stays as the fast
  path for top-level writes. Reindex is incremental, so no-op passes
  are cheap. Fixes `PersonaDaemonReindexStale` firing without cause.
- 2026-05-30: Commit 4 — MCP HTTP shell at `/mcp` (5 tools: chat, recall,
  list_personas, list_conversations, inbox_capture). Prometheus `/metrics`
  endpoint + scrape registration. Caddy route 28443 → 127.0.0.1:11550.
  Background backend prober (30s) populates `persona_daemon_backend_up`.
  brain-mcp gained 7th tool `inbox_capture`; daemon's `vault-writer-brain-mcp`
  adapter is the single writer to `_llm-inbox/<YYYY-MM-DD>/<HHMMSS>-<slug>.md`
  via bearer-auth JSON-RPC to brain-mcp (charter single-writer principle).
- 2026-05-29: Commit 3 — RAG over the brain vault. `VectorStore` (Float32
  BLOBs + WAL + in-memory mirror loaded at startup), markdown chunker
  (H2 boundaries / 400-token soft cap / frontmatter+code+MOC edge cases),
  notes-fs adapter (skips .obsidian/.trash/etc), brute-force cosine with
  frontmatter de-weighting. systemd.paths watches the vault (60s debounce)
  → POST /_internal/reindex. `persona-admin reindex [--full|--note]` CLI.
  Embed batch tuned for llama.cpp's slot mgmt (chunks well under model's
  2048 training context after several iterations).
- 2026-05-29: Commit 2 — initial module. Deno HTTP daemon (`/v1/chat/completions`,
  `/v1/models`, `/healthz`, `/_internal/conversations`). SQLite WAL store
  for conversations. Persona schema extended with `useMemory`/`useKnowledge`/
  `knowledgeTopK` via `_defaults.nix` merge pattern. `hwc-llm` gains
  `--new-conversation`, `--conversation`, `--print-id` flags that route
  through the daemon.
