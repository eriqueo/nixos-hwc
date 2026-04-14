# HWC Workspace Directory

**Domain-Aligned Script & Project Organization**

Workspace mirrors the `domains/` hierarchy. Each top-level folder corresponds to the domain it serves.

---

## Structure

```
workspace/
├── ai/              # domains/ai/ — bible automation, AI docs, prompts
├── automation/      # domains/automation/ — event hooks, n8n helpers
├── business/        # domains/business/ — estimator, calculator, API, estimate-automation
├── home/            # domains/home/ — scraper, mail, photo-dedup, SEO scraper
├── media/           # domains/media/ — youtube-services, media scripts, cleanup tools
├── monitoring/      # domains/monitoring/ — health checks, status scripts
├── nixos-dev/       # Repo development tools (not a domain)
└── system/          # domains/system/ — diagnostics, setup, system utilities
```

---

## Folder Descriptions

### ai/ — AI & ML Support
Bible automation scripts, AI documentation, prompt libraries.

### automation/ — Event-Driven Automation
- **hooks/** — download completion hooks (qbt, sabnzbd, slskd), media orchestrator, audiobook copier
- n8n-mcp-wrapper.sh

### business/ — Business Tools
- **bathroom-calculator/** — calculator PWA
- **estimator-pwa/** — estimator frontend (referenced by `domains/business/estimator/`)
- **remodel-api/** — backend API (referenced by `domains/business/parts/api.nix`)
- **estimate-automation/** — estimation pipeline

### home/ — User-Facing Tools
- **scraper/** — social media scraper (referenced by `domains/home/apps/scraper/`)
- **website_seo_scraper/** — SEO analysis tool
- **mail/** — mailbot
- **photo-dedup/** — duplicate photo finder (referenced by shell alias)

### media/ — Media Management
- **youtube-services/** — YT packages & transcript formatter (referenced by `domains/media/youtube/`)
- **scripts/** — beets helpers, media organizer, migration scripts
- **hooks/** — media-specific hooks
- **config-examples/** — reference configurations
- **cleanup-raw-files/** — raw file cleanup tool
- **n8n-workflows/** — media-related n8n workflow configs

### monitoring/ — System Health
Health check scripts: disk, GPU, journal errors, caddy, frigate, immich, media automation, service summaries.

### nixos-dev/ — Repository Development Tools
- Charter compliance (charter-lint.sh, autofix.sh)
- Build workflow (grebuild.sh)
- Module scaffolding (add-home-app.sh)
- Config analysis (graph/, nixos-translator/)
- Audit & linting tools

### system/ — System Infrastructure
- **diagnostics/** — troubleshooting tools, network diagnostics, config validation, GPU checks
- **setup/** — one-time deployment scripts (age keys, monitoring, permissions)
- System utilities: couchdb migration, secret manager, ZFS snapshots, container validation

---

## Three-Tier Architecture

### Tier 1: User Commands (Nix Derivations)
**Location**: `domains/home/environment/shell/parts/*.nix`
Wrapped Nix derivations in PATH. Examples: `grebuild`, `journal-errors`, `charter-lint`

### Tier 2: Workspace Scripts (Implementation)
**Location**: `workspace/*/`
Editable at runtime without NixOS rebuilds. This is where most scripts live.

### Tier 3: Domain-Specific Scripts
**Location**: `domains/*/scripts/` or `domains/*/parts/`
Tightly coupled to specific services — not promoted to workspace.

---

## Changelog

- 2026-03-25: Restructured to mirror domains/ hierarchy, consolidated duplicates, eliminated stale folders
- 2025-12-10: Reorganized from arbitrary categories to purpose-driven structure
