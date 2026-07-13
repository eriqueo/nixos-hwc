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
- 2026-07-13: `options.nix` folded inline into `index.nix` then the orphan file
  removed (AI-domain inline-options cleanup). Dropped the per-eval "AI Profile"
  informational warning that printed on every host eval and drowned out real
  warnings; detection is unchanged (still exported via `_module.args`).
- 2026-02-28: Updated GPU refs for infrastructure migration
- 2026-02-28: Added README for Charter Law 12 compliance
