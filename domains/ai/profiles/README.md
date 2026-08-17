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
│   └── definitions.nix   # Profile definitions
├── default.nix           # Import wrapper
├── index.nix             # Profiles implementation + inline options (Law 10)
└── README.md
```

## Changelog
- 2026-08-17: Structure block corrected — it still listed `options.nix`, deleted in 2026-05-21 (`4f199955`).
- 2026-06-10: `33154f59` — dropped the informational `AI Profile: …` `warnings` entry from `index.nix`. It printed on every eval of every host and drowned out real warnings; detection itself is unchanged and still exported via `_module.args.aiProfile` / `aiProfileName`.
- 2026-05-21: `4f199955` — deleted the orphan `profiles/options.nix` (-31) that the April sync merge had re-introduced; options live inline in `index.nix` per Law 10.
- 2026-04-14: `254f799c` — xps/remote-main sync merge updated `index.nix` and `parts/definitions.nix`.
- 2026-03-06: `0f8f427c` ("options move pt 1") — inlined `options.nix` into `index.nix`.
- 2026-02-28: Updated GPU refs for infrastructure migration
- 2026-02-28: Added README for Charter Law 12 compliance
