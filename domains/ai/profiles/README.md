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
└── index.nix            # Inline options + profiles implementation (Law 10)
```

## Changelog
- 2026-06-10: Dropped the per-eval "AI Profile" informational warning (33154f59) —
  it fired on every evaluation and said nothing actionable.
- 2026-05-21: Deleted the re-introduced `options.nix` orphan (4f199955); options
  live inline in `index.nix` since the 2026-03-06 options move (0f8f427c).
- 2026-02-28: Updated GPU refs for infrastructure migration
- 2026-02-28: Added README for Charter Law 12 compliance
