# domains/ai/

## Purpose

AI infrastructure: MCP servers. (Local inference — llama.cpp embeddings and whisper — lives in `domains/server/native/ai/`.)

## Boundaries

- **Manages**: MCP servers
- **Does NOT manage**: GPU drivers (→ `domains/infrastructure/hardware/gpu`), container runtime (→ `domains/server/`), secrets for API keys (→ `domains/secrets/`)

## Structure

```
domains/ai/
├── index.nix           # Domain aggregator
└── mcp/                # Model Context Protocol servers
```

Boundaries: this listing reflects what `ai/index.nix` actually imports. Any other directory you see in the tree (e.g. `anything-llm/`, `open-webui/`, `router/`, `agent/`, `personas/`, `profiles/`) used to live here and has been removed as dead code.

## Changelog

- 2026-09-19: **Retired the local chat stack**: removed `agent/` (hwc-ai-agent, the tool API built for Open WebUI; its audit log was last written Dec 2025), `personas/` (`hwc-llm`) and `profiles/` (hardware profile detection; nothing read `aiProfile`). Removed with them: `domains/server/native/ai/persona-daemon/`, the `llama-gpu` and `llama-cpu` services on hwc-server, their vhosts, probes and alerts. Evidence of non-use: persona-daemon's database held one conversation, from the day it was built (2026-05-30); 12 days of Caddy vhost logs showed no request to the chat hosts. Why it stalled: the models that fit a 4 GB P1000 or CPU RAM were too weak to trust, and Claude Code / Pi / T3 took over interactive work. What stays local: `llama-embed` (brain semantic search) and whisper. Hosted DX2 (`dx2.datax.to`) is the text model now. Machine configs for server, laptop and xps lost their `hwc.ai.profiles` / `hwc.ai.agent` settings. Recover from git history if needed.

- 2026-07-05: Removed `tools/` and `cloud/` (audit 2.2). `cloud` was never enabled anywhere; `tools` (charter-search/ai-doc/ai-commit/ai-lint) was enabled on the laptop but had zero shell-history usage ever — dead by the "deployed + used" principle. Laptop enable block removed. Recover from git history if needed.

- 2026-06-27: Retired the `ollama/` domain (container LLM stack: podman-ollama + pull/health/disk/model-health/idle/thermal timers). Broken since a Jul-2025 dangling `/var/lib/ollama → private/ollama` symlink and superseded by the native llama.cpp + persona-daemon stack (`domains/server/native/ai/`). Removed the import, the server `:11434` firewall hole, all `hwc.ai.ollama.*` refs (server/laptop/xps), and the laptop waybar-toggle `podman-ollama` sudo grant. The laptop waybar widget self-disables (`behavior.nix` reads the option via `attrByPath … false`). Local-LLM provider intent parked at `brain wiki/nixos/idea-refinery-local-llm-provider.md`.
- 2026-06-27: Retired `local-workflows/` wholesale (fileCleanup/autoDoc/chatCli + orphaned `api/` FastAPI client). All three were dead or superseded: fileCleanup collided with `inbox-janitor` (and was a destructive mover with its dryRun guard off), autoDoc's `post-rebuild-ai-docs` duplicated `grebuild-docs`/readme-freshness, and chatCli was redundant with `hwc-llm` + persona-daemon. Removed the import + all `hwc.ai.local-workflows.*` refs (server/laptop/xps). Part of the ollama-stack retirement (see next entry).
- 2026-06-10: profiles/index.nix — removed the informational "AI Profile: …" `warnings` entry. It printed on every eval of every host and drowned out real warnings; detection itself is unchanged and still exported via `_module.args.aiProfile` / `aiProfileName`.
- 2026-06-09: Removed `.nanoclaw-disabled/` (decommissioned 2026-05-29, superseded by Hermes; flagged in audit `docs/audit/2026-06-09-server-audit.md` §2.1, recoverable from git history).
- 2026-05-30: Persona-daemon Phase 2 + 2.5 landed (see `domains/server/native/ai/persona-daemon/`). `hwc-llm` gained `--new-conversation` / `--conversation <id>` / `--print-id` flags that route through the daemon for memory-backed multi-turn chats. `assistant`, `coder`, `thinker` personas now `useKnowledge=true` (top-K=6/6/10 respectively) — RAG over `/mnt/vaults/brain` via embeddings against `llama-embed`. `library/_defaults.nix` introduced for schema-merge pattern.
- 2026-05-29: Added `personas/` — persona library + `hwc-llm` CLI wrapping the two new llama.cpp endpoints (GPU LFM2-2.6B on :11500, CPU LFM2-24B-A2B on :11501). Phase 1 is stateless; SQLite-backed memory + HTTP daemon planned for Phases 2/3. See `domains/ai/personas/README.md`.
- 2026-05-21: removed remaining dead trees `anything-llm/`, `open-webui/`, `router/` (re-introduced at some point after the April cleanup but still unimported by `ai/index.nix`), the orphan `mcp/heartwood/` subdir (live MCP wiring moved to `domains/business/mcp/`, but that itself is also dead — separate commit), `local-workflows/parts/journaling.nix` (the restart-loop module the April note flagged), and orphan `options.nix` files in `ai/`, `agent/`, `cloud/`, `local-workflows/`, `mcp/`, `ollama/`, `profiles/`, `tools/` (legacy split files; options now declared inline in each `index.nix`). Verified via per-subdir `rg -ln "<name>" -t nix .` (zero external refs) and full eval (drv hashes unchanged).
- 2026-04-12: Major cleanup — removed dead modules: ai-bible (abandoned), anything-llm (unused), open-webui (zero traffic), router (skeleton), local-workflows API (unintegrated), journaling (restart-loop bug). Fixed nanoclaw path bug. -5,473 lines.
- 2026-03-25: Added Heartwood MCP Server to mcp/ subdomain (Phase 1: 63 JT tools via PAVE API)
- 2026-03-04: Moved ai-bible from domains/server/native/ai/ into domain; removed dead native/ai/ sub-modules
- 2026-02-26: Created README per Law 12
