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
├── profiles/           # Hardware profile detection and defaults
└── tools/              # AI CLI tools (charter-search, ai-doc, ai-commit)
```

## CLI Tools

- `ai-doc` - Generate documentation with AI
- `ai-commit` - AI-assisted commit messages
- `charter-search` - Search Charter compliance patterns

## Hardware Profiles

Auto-detects and configures based on available hardware:
- **NVIDIA GPU**: CUDA acceleration for Ollama
- **AMD GPU**: ROCm acceleration
- **CPU-only**: Optimized CPU inference

## Changelog

- 2026-04-12: Major cleanup — removed dead modules: ai-bible (abandoned), anything-llm (unused), open-webui (zero traffic), router (skeleton), local-workflows API (unintegrated), journaling (restart-loop bug). Fixed nanoclaw path bug. -5,473 lines.
- 2026-03-25: Added Heartwood MCP Server to mcp/ subdomain (Phase 1: 63 JT tools via PAVE API)
- 2026-03-04: Moved ai-bible from domains/server/native/ai/ into domain; removed dead native/ai/ sub-modules
- 2026-02-26: Created README per Law 12
