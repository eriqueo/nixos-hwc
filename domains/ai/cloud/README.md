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
- 2026-06-15: Backfill — Sprint 4.3 added cloud API infrastructure (43a97ab9); later picked up the broader ai-refactor, options.nix consolidation (Law 9/10), and ai-domain dead-tree cleanup.
- 2026-02-28: Added README for Charter Law 12 compliance
