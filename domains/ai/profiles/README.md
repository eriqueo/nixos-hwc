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
└── index.nix            # Options (inline, Law 10) + detection + _module.args export
```

## Changelog
- 2026-06-10: Dropped the per-eval "AI Profile: …" informational warning — it
  printed on every eval of every host and buried real warnings. Detection is
  unchanged and still exported via `_module.args` (`33154f59`)
- 2026-05-21: Deleted the orphaned `options.nix` stub (`4f199955`)
- 2026-03-06: Law 10 — options inlined into `index.nix`, `options.nix` removed (`0f8f427c`)
- 2026-02-28: Updated GPU refs for infrastructure migration
- 2026-02-28: Added README for Charter Law 12 compliance
