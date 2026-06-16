# AI Local Workflows

## Purpose
Local AI-powered automation workflows using Ollama.

## Boundaries
- Manages: File cleanup agent, auto-doc generator, chat CLI
- Does NOT manage: n8n workflows → `domains/automation/n8n/`

## Structure
```
local-workflows/
├── index.nix          # Options + implementation
├── default.nix        # Import wrapper
├── parts/
│   ├── file-cleanup.nix  # AI-powered file organization agent
│   ├── auto-doc.nix      # Documentation generator
│   └── chat-cli.nix      # Interactive CLI chat
└── README.md
```

## Changelog
- 2026-06-16: Mechanical sweep — Sprint 5.4 re-added a local-workflows HTTP API
  (`4fa98a31` / `27161ccb`); auto-doc subsystem hardened (`f15cfccd`, `49d22a3f`,
  `09c6a36e`, `b5a0b460` adds `mkForce` to auto-doc User/Group, `377f01b0`
  Phase-7 derived paths). Plus repo-wide carries: `ai refactor` (`5e27cd37`),
  Phase 1 charter namespace/paths (`437a8580`), Phase 1-3 tech-debt
  (`15f2d60f`), NixOS 24.11 deprecation fixes (`12587860`), dead-tree purge
  (`efd7063e`).
- 2026-04-12: Remove journaling (restart-loop bug, replaced by morning-briefing) and HTTP API (never integrated). Keep file-cleanup, auto-doc, chat-cli.
- 2026-02-28: Added README for Charter Law 12 compliance
