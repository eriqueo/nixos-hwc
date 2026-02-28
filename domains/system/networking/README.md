# System Networking

## Purpose
Network stack configuration: NetworkManager, SSH, Tailscale, Samba, firewall, DNS.

## Boundaries
- Manages: Network interfaces, firewall rules, VPN (Tailscale), file sharing (Samba), SSH
- Does NOT manage: Reverse proxy → `server/native/caddy/`, container networking → `server/containers/`

## Structure
```
networking/
├── index.nix    # Networking implementation
└── options.nix  # Networking options (ssh, tailscale, samba, firewall)
```

## Changelog
- 2026-02-28: Added README for Charter Law 12 compliance
