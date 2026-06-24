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
- 2026-02-28: Added README for Charter Law 12 compliance
- 2026-06-22: Refresh README (Sprint 4.3 added cloud API infrastructure; AI domain refactor + options.nix orphan cleanup; Charter Law 3 path-abstraction sweep).
