# nixos-hwc

NixOS flake managing two machines via domain-driven architecture. Charter v11.1.

## Machines
- **hwc-laptop** — NixOS desktop (Hyprland, dev tools, GPU)
- **hwc-server** — headless (Podman containers, Caddy, monitoring, media)
Always run `hostname` before nixos-rebuild. Hooks enforce this.

## Repo Map
```
flake.nix                          # Entry point (orchestration only)
machines/{laptop,server}/          # Hardware + profile imports
profiles/                          # Domain menus (system, home, server, media, etc.)
domains/
  home/apps/                       # Home Manager apps (waybar, hyprland, aerc, kitty, etc.)
  home/environment/shell/          # Shell config, scripts, env vars
  home/theme/                      # Gruvbox Material Dark palette + adapters
  networking/routes.nix            # ALL Caddy reverse proxy routes (ports 1443-18095)
  server/containers/               # Podman containers (immich, frigate, arr stack, etc.)
  secrets/declarations/            # agenix secret declarations
  secrets/parts/                   # Encrypted .age files
  paths/paths.nix                  # ALL path definitions (Law 3: no hardcoded paths elsewhere)
  system/core/                     # Boot, kernel, users
  automation/n8n/                  # n8n workflow automation
  business/heartwood-cms/          # Heartwood Craft CMS + 11ty site
  monitoring/                      # Grafana, Prometheus, Uptime Kuma
```

## Architecture Laws (errors if violated)
- **Namespace = folder**: `domains/home/apps/X/` → `hwc.home.apps.X.*` (no shortcuts)
- **No hardcoded paths**: use `config.hwc.paths.*` from `domains/paths/paths.nix`
- **osConfig safety**: use `osConfig.hwc or {}` or `attrByPath`, NEVER `osConfig.hwc.x or null`
- **Secrets**: always `group = "secrets"; mode = "0440"` (hooks remind on edit)
- **Assertions**: go INSIDE `config = lib.mkIf ...` block, not separate
- **Native services**: need `User = lib.mkForce "eric"` (mkForce is critical)
- **PGID=100** (users group), NOT 1000

## Recurring Mistakes (from git history)
- Port conflicts in routes.nix — always check existing assignments first
- Wrong paths — paths.nix is in `domains/paths/`, NOT `domains/system/core/`
- Container PGID=1000 — must be 100
- osConfig crashes — `osConfig.hwc.x or null` fails when osConfig={}

## Available Skills
`/build` `/check` `/cp` `/status` `/update` — and from system prompt:
`/add-server-container` `/add-home-app` `/secret-provision`
`/nixos-build-doctor` `/charter-check` `/module-migrate` `/system-checkup`

## MCP Servers
- **heartwood**: 63 JobTread tools (Heartwood Craft business data)
- **postgres**: databases heartwood_business, immich
- **n8n**: workflow automation (get/list/update/delete workflows)
- **memory**: persistent knowledge graph across sessions
- **prometheus**: service health metrics and container monitoring

## Before Any Change
- Read CHARTER.md if touching architecture
- `nix flake check` before and after changes

## On Commit
Update the changed domain's README.md: `## Structure` + `## Changelog` entry.
