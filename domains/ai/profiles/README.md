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
├── default.nix          # Import wrapper
└── index.nix            # Detection + inline options; exports via _module.args
```

## Changelog
- 2026-06-10: Dropped the informational `AI Profile: …` warning that printed on
  every eval of every host and drowned out real warnings. Detection unchanged;
  still exported via `_module.args`.
- 2026-03-06 → 2026-05-21: Law 10 — `options.nix` removed, options declared
  inline in `index.nix` (0f8f427c, re-applied in 4f199955).
- 2026-02-28: Updated GPU refs for infrastructure migration
- 2026-02-28: Added README for Charter Law 12 compliance
