# AI Ollama

## Purpose
Local LLM inference via Ollama with GPU acceleration.

## Boundaries
- Manages: Ollama service, model management, GPU passthrough
- Does NOT manage: Web UI → `open-webui/`, routing → `router/`

## Structure
```
ollama/
├── parts/         # Helper scripts
├── default.nix    # Package/overlay
├── index.nix      # Ollama implementation
└── options.nix    # Ollama options
```

## Changelog
- 2026-02-28: Updated GPU refs for infrastructure migration
- 2026-02-28: Added README for Charter Law 12 compliance
