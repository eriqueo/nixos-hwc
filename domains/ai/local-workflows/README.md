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
- 2026-04-12: Remove journaling (restart-loop bug, replaced by morning-briefing) and HTTP API (never integrated). Keep file-cleanup, auto-doc, chat-cli.
- 2026-02-28: Added README for Charter Law 12 compliance
- 2026-06-22: Refresh README (Sprint 5.4 HTTP API for local-workflows; NixOS 24.11 deprecation cleanup; auto-doc service hardening with mkForce User/Group; AI domain refactor + options.nix orphan cleanup).
