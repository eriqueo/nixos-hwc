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
- 2026-06-12: Backfill — Sprint 2/4.1/4.2 added health checks, model validation, declarative model config + disk monitoring (`f5c616ce`, `9453c19e`, `b64c19cb`). Smart controls landed to prevent runaway CPU/thermal issues (`efc7fc65` + `8a5d6962` toString fix). Auto-start disabled for ollama/anything-llm (`4791f47f`). Tmpfiles conflict + model-name mismatch fixed (`a1ccba6e`).
- 2026-02-28: Updated GPU refs for infrastructure migration
- 2026-02-28: Added README for Charter Law 12 compliance
