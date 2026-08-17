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
  _defaults.nix          # Shared persona defaults (schema-merge base)
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

- 2026-08-17: Structure block corrected — `library/_defaults.nix` and `default.nix` were missing from the listing.
- 2026-05-31: `40d9e2a3` — repaired orphan option-sets in `index.nix` that were breaking `nix flake check` (+15/-8).
- 2026-05-29: `007b5ab9` (persona-daemon 3/4) — `assistant`, `coder` and `thinker` gained the knowledge/RAG flag over the brain vault.
- 2026-05-29: `d5e5d002` (persona-daemon 2/4) — `index.nix` rewired to route through the Deno HTTP daemon with SQLite-backed conversation memory (+125/-31), and `library/_defaults.nix` added as the schema-merge base every persona now inherits from. This is the Phase 2/3 work the Roadmap below anticipated.
- 2026-05-29: Initial module. 5 personas (classifier, extractor, coder,
  assistant, thinker). Stateless CLI wrapping `llama-gpu` (port 11500)
  and `llama-cpu` (port 11501).
