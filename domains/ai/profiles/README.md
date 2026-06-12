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
- 2026-06-10: `5b53151b` — drop the per-eval "AI Profile" informational warning. It fired on every rebuild without conveying actionable info.
- 2026-06-12: Backfill — earlier `ai refactor`, `options move`, and the `efd7063e` dead-tree purge touched files here without changing the profile selection surface.
- 2026-02-28: Updated GPU refs for infrastructure migration
- 2026-02-28: Added README for Charter Law 12 compliance
