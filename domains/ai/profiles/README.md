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
├── index.nix            # Options (inline, Law 10) + profiles implementation
└── README.md
```

## Changelog
- 2026-06-10: Dropped the per-eval "AI Profile" informational warning
  (33154f59) — it fired on every evaluation and carried no actionable signal.
- 2026-05-21: Removed the orphaned `options.nix`; the `hwc.ai.profiles`
  options moved into `index.nix` per Law 10 (0f8f427c, 4f199955).
- 2026-02-28: Updated GPU refs for infrastructure migration
- 2026-02-28: Added README for Charter Law 12 compliance
