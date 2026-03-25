# domains/ai/

## Purpose

AI infrastructure including local LLMs (Ollama), web interfaces (Open WebUI, AnythingLLM), cloud API integration, MCP servers, and CLI tools for AI-assisted development workflows.

## Boundaries

- **Manages**: Ollama service, Open WebUI, AnythingLLM, MCP servers, AI CLI tools, local/cloud routing, hardware profile detection
- **Does NOT manage**: GPU drivers (→ `domains/infrastructure/hardware/gpu`), container runtime (→ `domains/server/`), secrets for API keys (→ `domains/secrets/`)

## Structure

```
domains/ai/
├── index.nix           # Domain aggregator
├── options.nix         # hwc.ai.* options
├── agent/              # HTTP tool agent
├── anything-llm/       # Local AI assistant with file access
├── cloud/              # Cloud AI API integration (Anthropic, OpenAI)
├── local-workflows/    # AI automation workflows
├── mcp/                # Model Context Protocol servers
├── ollama/             # Local LLM service
├── open-webui/         # Web UI for Ollama
├── profiles/           # Hardware profile detection and defaults
├── router/             # Local/cloud routing decisions
├── tools/              # AI CLI tools (charter-search, ai-doc, ai-commit)
└── ai-bible/           # AI-powered documentation system
```

## Configuration

```nix
hwc.ai = {
  enable = true;

  ollama = {
    enable = true;
    acceleration = "cuda";  # or "rocm" | "cpu"
  };

  openWebui = {
    enable = true;
    port = 3000;
  };

  cloud = {
    anthropic.enable = true;  # Requires secret: anthropic-api-key
    openai.enable = true;     # Requires secret: openai-api-key
  };
};
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

- 2026-03-25: Added Heartwood MCP Server to mcp/ subdomain (Phase 1: 63 JT tools via PAVE API)
- 2026-03-04: Moved ai-bible from domains/server/native/ai/ into domain; removed dead native/ai/ sub-modules
- 2026-02-26: Created README per Law 12
