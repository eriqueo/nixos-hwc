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
├── media-orchestrator.nix # Media pipeline orchestration service
├── README.md              # This file
└── audiobook-copier/
    ├── index.nix          # Audiobook copier deployment + service
    └── parts/
        └── config.nix     # Configuration options
```

### Workspace Source (`workspace/automation/hooks/`)
- `audiobook-copier.py` — Deployed to downloads/scripts/ by systemd install service
- `media-orchestrator.py` — Media pipeline event handler

## Changelog
- 2026-03-26: audiobook-copier workspace path updated from workspace/hooks/ to workspace/automation/hooks/ (domain alignment)
