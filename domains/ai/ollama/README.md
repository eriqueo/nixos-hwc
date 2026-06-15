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
- 2026-06-15: Backfill since 2026-02-28 — Sprint 1 `hwc.ai.*` namespace consolidation (f9b7fee5), Sprint 2 Ollama+Open WebUI health checks (f5c616ce), Sprint 4.1 model validation (9453c19e), Sprint 4.2 declarative model config + disk monitoring (b64c19cb), tmpfiles + model-name conflict fix (a1ccba6e), smart idle controls to prevent runaway CPU/thermal (efc7fc65 + 8a5d6962 toString fix), auto-start disabled (4791f47f), options.nix consolidation (Law 9/10), ai-domain dead-tree cleanup.
- 2026-02-28: Updated GPU refs for infrastructure migration
- 2026-02-28: Added README for Charter Law 12 compliance
