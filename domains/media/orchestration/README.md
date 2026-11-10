# Media Orchestration

## Purpose
Event-driven media pipeline automation: audiobook processing and media file orchestration.

## Boundaries
- Manages: Audiobook copier deployment, media orchestrator service
- Does NOT manage: Download clients (those are in `domains/media/{qbittorrent,sabnzbd}/`), media library scanning (Jellyfin/Lidarr handle that)

## Structure

audiobook-copier/index.nix exports a configured immutable Python wrapper and installs it at the existing downloads/scripts/audiobook-copier.py path. The wrapper preserves environment overrides and delegates to workspace/automation/hooks/audiobook-copier.py. A nonblocking process lock gives one copier ownership of state and .abs-copied markers; a busy hook fails for the next sweep to recover. Dry runs do not write state or request scans.
```
orchestration/
├── index.nix              # Aggregator
├── README.md              # This file
└── audiobook-copier/
    └── index.nix          # Configured Python wrapper, installation and state directory
```

### Workspace Source (`workspace/automation/hooks/`)
- `audiobook-copier.py` — Deployed to downloads/scripts/ by systemd install service

## Changelog

- 2026-11-09: Share copy behavior with hot-sweep, wire existing options into the wrapper, preserve marker/state formats and remove the trivial tmpfiles part.
- 2026-07-05: Removed `media-orchestrator/` module (audit 2.2: never enabled; cp-path repoint in the July audit was eval-only). audiobook-copier is now the domain's only member.
- 2026-03-26: audiobook-copier workspace path updated from workspace/hooks/ to workspace/automation/hooks/ (domain alignment)
