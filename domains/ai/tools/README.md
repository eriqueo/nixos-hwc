# AI Tools

## Purpose
AI CLI tools for Charter compliance, documentation, and Ollama interaction.

## Boundaries
- Manages: AI tool packages, utility scripts
- Does NOT manage: MCP tools → `mcp/`

## Tools

### ollama-wrapper.sh
Thermal-aware Ollama wrapper with Charter integration for general AI tasks.

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
- 2026-04-12: Remove dead scripts (grebuild-docs, readme-butler, changelog-writer, setup-changelog-model) and post-rebuild-ai-docs service.
- 2026-03-18: Add README butler script to automate AI-driven changelog generation in grebuild workflow.
- 2026-03-14: Fix AI tooling by using pre-increment to avoid set -e exit on first domain.
- 2026-03-09: Add custom AI model for generating human-readable changelogs
- 2026-03-09: Add readme-butler.sh for automated Law 12 changelog updates
- 2026-02-28: Added README for Charter Law 12 compliance
