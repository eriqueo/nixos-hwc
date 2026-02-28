# System Services

## Purpose
System-level services that support the OS and user environment.

## Boundaries
- Manages: Audio/portals, backups, monitoring, notifications, session management, VPN
- Does NOT manage: Application services → `server/`, user services → `home/`

## Structure
```
services/
├── backup/              # Restic/backup configuration
├── borg/                # Borg backup service
├── hardware/            # Audio, peripherals, Bluetooth
├── monitoring/          # System monitoring
├── ntfy/                # Push notifications
├── polkit/              # Privilege escalation rules
├── protonmail-bridge/   # ProtonMail integration
├── session/             # Desktop session management
├── shell/               # System shell configuration
├── vpn/                 # VPN client configuration
├── index.nix            # Services aggregator
└── options.nix          # Services root options
```

## Changelog
- 2026-02-28: Added peripherals to hardware/ from infrastructure migration
- 2026-02-28: Added README for Charter Law 12 compliance
