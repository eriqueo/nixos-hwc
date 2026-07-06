# personas

`hwc.ai.personas` — a curated system-prompt library plus the `hwc-llm` CLI
that routes prompts to the right local llama.cpp service
(`domains/server/native/ai/llama-cpp`).

## Personas

| Name | Backend | Use case |
|---|---|---|
| `classifier` | GPU (LFM2-2.6B) | One-token label selection |
| `extractor`  | GPU (LFM2-2.6B) | Structured JSON extraction |
| `coder`      | GPU (LFM2-2.6B) | Code-first answers |
| `assistant`  | GPU (LFM2-2.6B) | General short Q&A |
| `thinker`    | CPU (LFM2-24B-A2B) | Multi-step reasoning |

## Usage

```bash
hwc-llm --list
hwc-llm classifier "Pick one of [spam, ham]: 'free crypto for the first 100 visitors'"
hwc-llm extractor 'Pull {name, amount, due_date} as JSON: "Invoice from Acme for $1240 due May 30"'
hwc-llm thinker  "Why does llama.cpp still load cuBLAS when invoked with -ngl 0?"
cat README.md | hwc-llm coder -
```

## Adding a persona

Drop two files into `library/`:

- `mypersona.nix` — `{ model = "gpu"; temperature = 0.2; topP = 0.9; maxTokens = 256; description = "..."; }`
- `mypersona.md`  — system-prompt body (plain text; fed verbatim to the model)

Rebuild and the persona becomes available. The list is derived from
`library/*.nix` at evaluation time — no central registry to maintain.

## Structure

```
library/
  _defaults.nix          # Per-persona schema defaults (useMemory/useKnowledge/knowledgeTopK)
  classifier.{nix,md}    # GPU label classification
  extractor.{nix,md}     # GPU JSON extraction
  coder.{nix,md}         # GPU code-first
  assistant.{nix,md}     # GPU general
  thinker.{nix,md}       # CPU multi-step reasoning
default.nix              # Import wrapper
index.nix                # Inline options + library load + hwc-llm wrapper
README.md
```

## Roadmap

- **Phase 1 (this)** — stateless CLI. Each `hwc-llm` invocation is
  independent; no conversation memory.
- **Phase 2** — SQLite-backed conversations via a `--conversation <id>`
  flag, so multi-turn chats round-trip locally.
- **Phase 3** — wrap the same core as an OpenAI-compatible HTTP daemon on
  `127.0.0.1:11550` (Caddy `28443`) so hermes, lead-scout, n8n and other
  callers can hit one persona-aware endpoint instead of three.

## Changelog

- 2026-07-06: Fixed an orphan option-set in `index.nix` that broke `nix flake check` —
  the `hwc.server.ai.personaDaemon.personaManifestFile` set is now gated on the daemon
  module being in scope (only hwc-server imports persona-daemon), so hwc-laptop/hwc-xps
  eval cleanly.
- 2026-05-29 (persona-daemon Phase 2–3): Personas extended for the new
  `hwc.server.ai.personaDaemon` (Deno HTTP daemon on `127.0.0.1:11550`, delivering the
  Roadmap Phase 2/3 goals). Added `library/_defaults.nix` with three new per-persona
  fields — `useMemory`, `useKnowledge`, `knowledgeTopK`. assistant/coder/thinker set
  `useMemory=true` and (after the RAG commit) `useKnowledge=true` (topK 6/6/10);
  classifier/extractor stay stateless. `hwc-llm` gained `--conversation`,
  `--new-conversation`, `--print-id`.
- 2026-05-29: Initial module. 5 personas (classifier, extractor, coder,
  assistant, thinker). Stateless CLI wrapping `llama-gpu` (port 11500)
  and `llama-cpu` (port 11501).
