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
- 2026-06-10: Drop the per-eval "AI Profile" informational warning (5b53151b) — was firing on every build and adding nothing actionable.
- 2026-06-15: Backfill since 2026-02-28 — ai refactor sweep, options.nix consolidation (Law 9/10), ai-domain dead-tree cleanup.
- 2026-02-28: Updated GPU refs for infrastructure migration
- 2026-02-28: Added README for Charter Law 12 compliance
