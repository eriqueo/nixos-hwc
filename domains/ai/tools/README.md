# AI Tools

## Purpose
AI CLI tools for Charter compliance, documentation, and local LLM interaction
(llama.cpp's OpenAI-compatible server).

## Boundaries
- Manages: AI tool packages, utility scripts
- Does NOT manage: MCP tools → `mcp/`

## Tools

### ollama-wrapper.sh
Thermal-aware llama.cpp wrapper with Charter integration for general AI tasks.
Talks to llama.cpp's OpenAI-compatible `/v1/chat/completions` on 127.0.0.1:11500
(env: `LLM_ENDPOINT`, `LLM_MODEL`). Thermal guard watches the dGPU (`GPU_WARN`/
`GPU_CRIT`, 80/90 °C) and the CPU; binary name kept as `ollama-wrapper`.

### charter-search.sh
Extracts relevant Charter context by domain/task type.

### CLI wrappers
- `ai-doc` — documentation generator via ollama-wrapper
- `ai-commit` — commit message generator via ollama-wrapper
- `ai-lint` — Charter compliance checker via ollama-wrapper

## Structure
```
tools/
├── index.nix                   # Module definition
├── default.nix                 # Import wrapper
├── parts/
│   ├── ollama-wrapper.sh       # Thermal-aware AI wrapper
│   └── charter-search.sh       # Charter context extraction
└── README.md
```

## Changelog
- 2026-06-28: Rewire ollama-wrapper from the Ollama `/api/generate` API to
  llama.cpp's OpenAI `/v1/chat/completions` (endpoint 127.0.0.1:11500, model
  alias lfm2-2.6b). Thermal guard extended to the dGPU (GPU_WARN/GPU_CRIT 80/90)
  since inference now runs on the NVIDIA card; only one chat model is served so
  a thermal warning logs but no longer downgrades. The lingering grebuild-docs.sh
  (declared removed 2026-04-12 but still on disk, unwired) was repointed to the
  same endpoint to defuse the latent podman-ollama/:11434 coupling.
- 2026-04-12: Remove dead scripts (grebuild-docs, readme-butler, changelog-writer, setup-changelog-model) and post-rebuild-ai-docs service.
- 2026-03-18: Add README butler script to automate AI-driven changelog generation in grebuild workflow.
- 2026-03-14: Fix AI tooling by using pre-increment to avoid set -e exit on first domain.
- 2026-03-09: Add custom AI model for generating human-readable changelogs
- 2026-03-09: Add readme-butler.sh for automated Law 12 changelog updates
- 2026-02-28: Added README for Charter Law 12 compliance
