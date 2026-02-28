# AI Open WebUI

## Purpose
Web interface for local and cloud LLM interaction.

## Boundaries
- Manages: Open WebUI container, tools, pipelines
- Does NOT manage: LLM inference → `ollama/`, routing → `router/`

## Structure
```
open-webui/
├── tools/         # Custom tools and functions
├── default.nix    # Package/overlay
├── index.nix      # Open WebUI implementation
└── options.nix    # Open WebUI options
```

## Changelog
- 2026-02-28: Added README for Charter Law 12 compliance
