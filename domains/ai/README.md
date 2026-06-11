# domains/ai/

## Purpose

AI infrastructure including local LLMs (Ollama), cloud API integration, MCP servers, CLI tools, and agent orchestration.

## Boundaries

- **Manages**: Ollama service, MCP servers, AI CLI tools, NanoClaw agent, hardware profile detection, local workflows (file-cleanup, auto-doc, chat-cli)
- **Does NOT manage**: GPU drivers (→ `domains/infrastructure/hardware/gpu`), container runtime (→ `domains/server/`), secrets for API keys (→ `domains/secrets/`)

## Structure

```
domains/ai/
├── index.nix           # Domain aggregator
├── agent/              # HTTP tool agent
├── cloud/              # Cloud AI API integration (Anthropic, OpenAI)
├── local-workflows/    # AI automation (file-cleanup, auto-doc, chat-cli)
├── mcp/                # Model Context Protocol servers
├── nanoclaw/           # NanoClaw AI agent orchestrator (Slack)
├── ollama/             # Local LLM service
├── personas/           # `hwc-llm` persona CLI wrapping llama.cpp endpoints
├── profiles/           # Hardware profile detection and defaults
└── tools/              # AI CLI tools (charter-search, ai-doc, ai-commit)
```

Boundaries: this listing reflects what `ai/index.nix` actually imports. Any other directory you see in the tree (e.g. `anything-llm/`, `open-webui/`, `router/`) used to live here and has been removed as dead code.

## CLI Tools

- `ai-doc` - Generate documentation with AI
- `ai-commit` - AI-assisted commit messages
- `charter-search` - Search Charter compliance patterns
- `hwc-llm` - Persona-aware CLI wrapping local llama.cpp (LFM2-2.6B GPU / LFM2-24B-A2B CPU); see `personas/`

## Hardware Profiles

Auto-detects and configures based on available hardware:
- **NVIDIA GPU**: CUDA acceleration for Ollama
- **AMD GPU**: ROCm acceleration
- **CPU-only**: Optimized CPU inference

## Changelog

- 2026-06-10: profiles/index.nix — removed the informational "AI Profile: …" `warnings` entry. It printed on every eval of every host and drowned out real warnings; detection itself is unchanged and still exported via `_module.args.aiProfile` / `aiProfileName`.
- 2026-06-09: Removed `.nanoclaw-disabled/` (decommissioned 2026-05-29, superseded by Hermes; flagged in audit `docs/audit/2026-06-09-server-audit.md` §2.1, recoverable from git history).
- 2026-05-30: Persona-daemon Phase 2 + 2.5 landed (see `domains/server/native/ai/persona-daemon/`). `hwc-llm` gained `--new-conversation` / `--conversation <id>` / `--print-id` flags that route through the daemon for memory-backed multi-turn chats. `assistant`, `coder`, `thinker` personas now `useKnowledge=true` (top-K=6/6/10 respectively) — RAG over `/mnt/vaults/brain` via embeddings against `llama-embed`. `library/_defaults.nix` introduced for schema-merge pattern.
- 2026-05-29: Added `personas/` — persona library + `hwc-llm` CLI wrapping the two new llama.cpp endpoints (GPU LFM2-2.6B on :11500, CPU LFM2-24B-A2B on :11501). Phase 1 is stateless; SQLite-backed memory + HTTP daemon planned for Phases 2/3. See `domains/ai/personas/README.md`.
- 2026-05-21: removed remaining dead trees `anything-llm/`, `open-webui/`, `router/` (re-introduced at some point after the April cleanup but still unimported by `ai/index.nix`), the orphan `mcp/heartwood/` subdir (live MCP wiring moved to `domains/business/mcp/`, but that itself is also dead — separate commit), `local-workflows/parts/journaling.nix` (the restart-loop module the April note flagged), and orphan `options.nix` files in `ai/`, `agent/`, `cloud/`, `local-workflows/`, `mcp/`, `ollama/`, `profiles/`, `tools/` (legacy split files; options now declared inline in each `index.nix`). Verified via per-subdir `rg -ln "<name>" -t nix .` (zero external refs) and full eval (drv hashes unchanged).
- 2026-04-12: Major cleanup — removed dead modules: ai-bible (abandoned), anything-llm (unused), open-webui (zero traffic), router (skeleton), local-workflows API (unintegrated), journaling (restart-loop bug). Fixed nanoclaw path bug. -5,473 lines.
- 2026-03-25: Added Heartwood MCP Server to mcp/ subdomain (Phase 1: 63 JT tools via PAVE API)
- 2026-03-04: Moved ai-bible from domains/server/native/ai/ into domain; removed dead native/ai/ sub-modules
- 2026-02-26: Created README per Law 12
