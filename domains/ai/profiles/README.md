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
└── index.nix            # Inline options + profile detection
```

## Changelog
- 2026-06-10: Dropped the per-eval "AI Profile: …" informational warning
  (`33154f59`) — it printed on every eval of every host and drowned out real
  warnings. Detection unchanged; still exported via `_module.args`.
- 2026-05-21: Dead-tree / `options.nix`-orphan cleanup across `domains/ai`
  (`4f199955`).
- 2026-03-06: Law 10 compliance — `options.nix` deleted, its declarations
  inlined into `index.nix` (`0f8f427c`). `Structure` updated to match.
- 2026-02-28: Updated GPU refs for infrastructure migration
- 2026-02-28: Added README for Charter Law 12 compliance
