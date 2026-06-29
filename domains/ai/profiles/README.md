# AI Profiles

## Purpose
Machine-specific AI capability profiles based on hardware.

## Boundaries
- Manages: AI profile definitions (GPU type, RAM allocation), capability detection
- Does NOT manage: Service config → `ollama/`, `open-webui/`

## Structure
```
profiles/
├── parts/         # Profile definitions
├── default.nix    # Package/overlay
├── index.nix      # Profiles implementation
└── options.nix    # Profiles options
```

## Changelog
- 2026-06-29: Drop per-eval "AI Profile" informational warning (5b53151b); options moved in 0f8f427c; ai refactor populated `index.nix`/`options.nix` and added `default.nix` (5e27cd37); transient orphan `options.nix` removed again in efd7063e.
- 2026-02-28: Updated GPU refs for infrastructure migration
- 2026-02-28: Added README for Charter Law 12 compliance
