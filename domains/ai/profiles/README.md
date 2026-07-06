# AI Profiles

## Purpose
Machine-specific AI capability profiles based on hardware.

## Boundaries
- Manages: AI profile definitions (GPU type, RAM allocation), capability detection
- Does NOT manage: Service config → `ollama/`, `open-webui/`

## Structure
```
profiles/
├── parts/
│   └── definitions.nix  # Profile definitions
├── default.nix          # Package/overlay
└── index.nix            # Profiles implementation + inline options
```

## Changelog
- 2026-07-06: Dropped the per-eval "AI Profile" informational warning that printed on
  every host eval and drowned out real warnings (detection unchanged, still exported via
  `_module.args`). Also: options moved inline into `index.nix` and the split `options.nix`
  deleted ("options move pt 1"); Structure block corrected to match.
- 2026-02-28: Updated GPU refs for infrastructure migration
- 2026-02-28: Added README for Charter Law 12 compliance
