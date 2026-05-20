# nixos-hwc

NixOS flake managing two machines via domain-driven architecture. Charter v11.2.

## Machines
- **hwc-laptop** — NixOS desktop (Hyprland, dev tools, GPU)
- **hwc-server** — headless (Podman containers, Caddy, monitoring, media)
Always run `hostname` before nixos-rebuild. Hooks enforce this.

## Home Manager workflows
Home Manager is wired **two ways from the same source** (`profiles/home-session.nix`
+ `machines/<host>/home.nix`):

- **HM-as-module** — runs inside `nixos-rebuild switch --flake .#hwc-<host>`.
  This is what activates on boot. Use for **system or mixed** changes.
- **HM-as-flake** — `homeConfigurations."eric@hwc-<host>"` in `flake.nix`.
  Run with `home-manager switch --flake ~/.nixos#eric@$(hostname)` (alias `hms`).
  Use for **HM-only** changes (anything under `domains/home/`, `profiles/home-session.nix`,
  `machines/<host>/home.nix`). Fast (~5–10s), no sudo.

**Rule**: HM-only edits → `hms`. System or mixed edits → `nixos-rebuild`.
Don't alternate on the same machine without thinking — each path keeps its own
HM profile generation, so files placed by one will trip "existing file in the way"
errors when the other tries to claim them. The module path sets
`backupFileExtension = "backup"`; the standalone path has no such cushion.

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

## MCP vs Bash — Token Efficiency
On hwc-server, prefer direct bash over MCP for server ops. MCP wraps shell
commands in JSON — costs ~3x more tokens for equivalent info.

**Use bash for**: systemctl, journalctl, podman, df, sqlite3, curl, anything
you can run directly on the box.

**Use MCP only when**:
- Tool hits an external API with no CLI equivalent (JobTread `jt_*`, n8n workflows)
- Tool does complex business logic (estimator, mail health)
- Tool evaluates Nix expressions (`hwc_config_*`)

**Skip MCP for**: monitoring health checks, service status, storage status,
journal errors, container stats — these just run shell commands with JSON tax.

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
