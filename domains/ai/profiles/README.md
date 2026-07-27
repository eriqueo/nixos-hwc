# AI Profiles

## Purpose
Machine-specific AI capability profiles based on hardware.

## Boundaries
- Manages: AI profile definitions (GPU type, RAM allocation), capability detection
- Does NOT manage: Service config → `ollama/`, `open-webui/`

## Structure
```
profiles/
├── parts/         # Profile definitions (definitions.nix)
├── default.nix    # Package/overlay
└── index.nix      # Profiles implementation + inline options
```

## Changelog
- 2026-06-10: Dropped the per-eval "AI Profile" informational warning (noise on every host eval); detection unchanged, still exported via `_module.args` (33154f59).
- 2026-05-21 / 2026-03-06: Removed `options.nix` — options now declared inline in `index.nix` (0f8f427c, 4f199955). Structure updated to match.
- 2026-02-28: Updated GPU refs for infrastructure migration
- 2026-02-28: Added README for Charter Law 12 compliance
