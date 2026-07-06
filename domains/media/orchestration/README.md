# Media Orchestration

## Purpose
Event-driven media pipeline automation: audiobook processing and media file orchestration.

## Boundaries
- Manages: Audiobook copier deployment, media orchestrator service
- Does NOT manage: Download clients (those are in `domains/media/{qbittorrent,sabnzbd}/`), media library scanning (Jellyfin/Lidarr handle that)

## Structure
```
orchestration/
├── index.nix              # Aggregator
├── README.md              # This file
└── audiobook-copier/
    ├── index.nix          # Audiobook copier deployment + service
    └── parts/
        └── config.nix     # Configuration options
```

### Workspace Source (`workspace/automation/hooks/`)
- `audiobook-copier.py` — Deployed to downloads/scripts/ by systemd install service

## Changelog
- 2026-07-05: Removed `media-orchestrator/` module (audit 2.2: never enabled; cp-path repoint in the July audit was eval-only). audiobook-copier is now the domain's only member.
- 2026-03-26: audiobook-copier workspace path updated from workspace/hooks/ to workspace/automation/hooks/ (domain alignment)
