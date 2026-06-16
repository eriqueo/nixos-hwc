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
- 2026-06-16: Mechanical sweep — Sprint 1 `hwc.ai.*` consolidation
  (`f9b7fee5`), Sprint 2 health checks (`f5c616ce`), Sprint 4.1 model
  validation + health checks (`9453c19e`), Sprint 4.2 declarative model config
  + disk monitoring (`b64c19cb`), smart-controls anti-runaway-CPU
  (`efc7fc65`, `8a5d6962`), tmpfiles + model-name conflict fix
  (`a1ccba6e`), and `4791f47f` disables auto-start for ollama / anything-llm.
  Plus repo-wide carries: `ai refactor` (`5e27cd37`), options moves
  (`0f8f427c`), dead-tree purge (`efd7063e`).
- 2026-02-28: Updated GPU refs for infrastructure migration
- 2026-02-28: Added README for Charter Law 12 compliance
