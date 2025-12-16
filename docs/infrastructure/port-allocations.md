# Port Allocations (In-Repo Registry)

Purpose: avoid duplicate/overlapping `networking.firewall.*` rules by keeping a human-readable map of ports, owners, and locations. Keep this file updated when adding services or changing ports.

## TCP

| Port | Service | Location (module/profile) |
| ---: | ------- | ------------------------- |
| 5000 | Frigate (API) | profiles/server.nix (`firewall.extraTcpPorts`) |
| 5030 | SLSKD | profiles/server.nix |
| 5055 | Jellyseerr | profiles/server.nix |
| 7878 | Radarr | profiles/server.nix |
| 8080 | qBittorrent (via Gluetun) | profiles/server.nix |
| 8081 | SABnzbd | profiles/server.nix |
| 8096 | Jellyfin | profiles/server.nix |
| 8686 | Lidarr | profiles/server.nix |
| 8888 | Receipt API | profiles/server.nix |
| 8989 | Sonarr | profiles/server.nix |
| 9090 | Prometheus | profiles/server.nix |
| 9093 | Alertmanager | profiles/server.nix |
| 9696 | Prowlarr | profiles/server.nix |
| 11434 | Ollama | profiles/server.nix |
| 2283 | Immich | profiles/server.nix |
| 3000 | Grafana | profiles/server.nix |
| 4533 | Navidrome | profiles/server.nix |
| 5432 | PostgreSQL (internal) | profiles/server.nix |
| 5678 | n8n | domains/server/monitoring/index.nix (n8n enable) |

## UDP

| Port | Service | Location (module/profile) |
| ---: | ------- | ------------------------- |
| 7359 | Jellyfin discovery | profiles/server.nix |
| 8555 | Frigate | profiles/server.nix |
| 50300 | SLSKD | profiles/server.nix |

## Notes
- When adding a new service port, update the appropriate table above with module/profile reference.
- If a module manages its own firewall rules, include the path in the Location column.
- Prefer `hwc.server.*` options to open ports; avoid scattering raw `networking.firewall` edits across modules.
