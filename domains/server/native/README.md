# Server Native

## Purpose
Native NixOS services (non-containerized workloads).

## Boundaries
- Manages: systemd services, native daemons, direct NixOS service config
- Does NOT manage: Containerized services → `containers/`

## Structure
```
native/
├── ai/              # AI services (ollama native)
├── backup/          # Backup services
├── beets-native/    # Music organization
├── couchdb/         # Document database
├── downloaders/     # Download managers
├── frigate/         # NVR system
├── immich/          # Photo management (native)
├── jellyfin/        # Media server (native)
├── media/           # Media services
├── n8n/             # Workflow automation
├── retroarch/       # Retro gaming
└── youtube/         # YouTube services
```

## Changelog
- 2026-02-28: Added README for Charter Law 12 compliance
