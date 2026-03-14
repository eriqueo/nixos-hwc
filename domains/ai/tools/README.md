# AI Tools

## Purpose
AI tooling and helper utilities for documentation, changelog generation, and Charter compliance automation.

## Boundaries
- Manages: AI tool packages, utility scripts, grebuild integrations
- Does NOT manage: MCP tools → `mcp/`, Open WebUI tools → `open-webui/tools/`

## Tools

### readme-butler.sh
Context-aware README changelog updater for Law 12 compliance. Runs after `git commit` but before `git push` in the grebuild workflow.

**How it works:**
1. Discovers domains changed in HEAD~1..HEAD
2. For each domain with README.md:
   - Reads README context (Purpose/Overview sections)
   - Reads git diff for the domain
   - Reads existing changelog entries (format guide)
   - Generates AI changelog entry via Ollama (qwen2.5-coder:3b)
   - Appends to ## Changelog section
3. Amends the current commit with README updates

**Environment variables:**
- `OLLAMA_ENDPOINT` - Ollama API URL (default: http://localhost:11434)
- `NIXOS_DIR` - NixOS config directory (default: /home/eric/.nixos)
- `MODEL` - AI model to use (default: qwen2.5-coder:3b)
- `TIMEOUT` - Ollama request timeout in seconds (default: 30)

### ollama-wrapper.sh
Thermal-aware Ollama wrapper with Charter integration for general AI tasks.

### charter-search.sh
Extracts relevant Charter context by domain/task type.

### grebuild-docs.sh
Post-rebuild documentation generator (runs asynchronously via systemd).

## Structure
```
tools/
├── index.nix                   # Module definition, systemd service
├── default.nix                 # Import wrapper
├── parts/
│   ├── readme-butler.sh        # Law 12 changelog automation
│   ├── changelog-writer.modelfile  # Custom Ollama model for changelogs
│   ├── setup-changelog-model.sh    # One-time model setup script
│   ├── ollama-wrapper.sh       # Thermal-aware AI wrapper
│   ├── charter-search.sh       # Charter context extraction
│   └── grebuild-docs.sh        # Post-rebuild docs generator
└── README.md
```

## Setup

To create the custom changelog-writer model (one-time):
```bash
./domains/ai/tools/parts/setup-changelog-model.sh
```

## Changelog
- 2026-03-14: Fix AI tooling by using pre-increment to avoid set -e exit on first domain.
- 2026-03-09: Add custom AI model for generating human-readable changelogs
- 2026-03-09: Add readme-butler.sh for automated Law 12 changelog updates
- 2026-02-28: Added README for Charter Law 12 compliance
