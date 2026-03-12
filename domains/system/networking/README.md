# System Networking

## Purpose
Network stack configuration: NetworkManager, SSH, Tailscale, Samba, firewall, DNS.

## Boundaries
- Manages: Network interfaces, firewall rules, VPN (Tailscale), file sharing (Samba), SSH
- Does NOT manage: Reverse proxy → `server/native/caddy/`, container networking → `server/containers/`

## Structure
```
networking/
└── index.nix    # Networking implementation (options inlined)
```

## Changelog
- 2026-02-28: Added README for Charter Law 12 compliance
- 2026-03-12: Inlined options.nix into index.nix; removed separate options.nix
