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
- 2026-06-22: Refresh README (auto-start disabled for ollama/anything-llm; smart controls + idleMinutes toString fix to prevent runaway CPU/thermal; tmpfiles + model-name fix; declarative model config + disk monitoring; Sprint 4.1 health checks; Sprint 1 namespace consolidation).
