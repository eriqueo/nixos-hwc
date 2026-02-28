# AI Router

## Purpose
Local-first AI model routing with cloud fallback.

## Boundaries
- Manages: Request routing, model selection, endpoint proxying
- Does NOT manage: LLM inference → `ollama/`, profiles → `profiles/`

## Structure
```
router/
├── parts/         # Router helpers
├── default.nix    # Package/overlay
├── index.nix      # Router implementation
└── options.nix    # Router options
```

## Changelog
- 2026-02-28: Added README for Charter Law 12 compliance
