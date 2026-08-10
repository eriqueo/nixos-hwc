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

- `mypersona.nix` — `import ./_defaults.nix // { model = "gpu"; temperature = 0.2; description = "..."; }`
  (override only what differs; memory/knowledge gates `useMemory`,
  `useKnowledge`, `knowledgeTopK` are consumed by persona-daemon)
- `mypersona.md`  — system-prompt body (plain text; fed verbatim to the model)

Rebuild and the persona becomes available. The list is derived from
`library/*.nix` at evaluation time — no central registry to maintain.

## Structure

```
library/
  _defaults.nix          # Per-field defaults every persona merges from
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

- **Phase 1 — done.** Stateless CLI; each `hwc-llm` invocation is independent.
  Still the default path, and it does not depend on the daemon.
- **Phase 2 — done (2026-05-29).** `--conversation <id>` / `--new-conversation`
  route through persona-daemon's SQLite conversation memory.
- **Phase 3 — done (2026-05-29).** The OpenAI-compatible daemon lives in
  `domains/server/native/ai/persona-daemon` and is reached via `daemonUrl`
  (`http://127.0.0.1:11550`); this module hands it the persona manifest.

## Changelog

- 2026-05-31: Gated the `hwc.server.ai.personaDaemon.personaManifestFile` set on
  `options.hwc.server.ai ? personaDaemon` (40d9e2a3) — personas is imported by
  every host, persona-daemon only by hwc-server, so the unconditional set broke
  `nix flake check` on the other two.
- 2026-05-29: Phase 2/3 landed — `library/_defaults.nix` added and every persona
  now merges from it; `daemonUrl` option (default `http://127.0.0.1:11550`) and
  the `--conversation` memory path in `hwc-llm` route through persona-daemon
  (d5e5d002); `useKnowledge`/`knowledgeTopK` gates added for brain-vault RAG
  (007b5ab9).
- 2026-05-29: Initial module. 5 personas (classifier, extractor, coder,
  assistant, thinker). Stateless CLI wrapping `llama-gpu` (port 11500)
  and `llama-cpu` (port 11501).
