# AI Cloud

## Purpose
Cloud AI provider integrations (OpenAI, Anthropic, etc).

## Boundaries
- Manages: API configurations, cloud model access
- Does NOT manage: Local inference → `ollama/`, routing → `router/`

## Structure
```
cloud/
└── (cloud provider configurations)
```

## Changelog
- 2026-06-29: Charter refactor: added `default.nix` (5e27cd37); orphan `options.nix` deleted in efd7063e; options sweep (0f8f427c).
- 2026-02-28: Added README for Charter Law 12 compliance
