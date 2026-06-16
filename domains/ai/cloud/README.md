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
- 2026-06-16: Mechanical sweep — Sprint 4.3 added cloud-API scaffolding
  (`43a97ab9`), then dir carried along by repo-wide `ai refactor` (`5e27cd37`),
  options moves (`0f8f427c`), dead-tree purge (`efd7063e`), and Phase 1-3
  tech-debt cleanup (`15f2d60f`). No cloud-specific behavior change to call out.
- 2026-02-28: Added README for Charter Law 12 compliance
