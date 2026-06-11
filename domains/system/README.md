# System Domain

## Scope & Boundary
- Core OS lane: accounts, networking, filesystem scaffolding, base services, and packages other domains rely on.
- Namespaces match paths (`hwc.system.*`, `hwc.filesystem.*` shortcut for core/filesystem) per Charter Law 2.
- No Home Manager logic lives here; cross-lane assertions are guarded so the system lane stands alone.

## Layout
```
domains/system/
├── core/
│   ├── filesystem.nix    # Filesystem tmpfiles; options at hwc.system.core.filesystem (alias: hwc.filesystem)
│   ├── packages.nix      # Base/server/security package bundles (hwc.system.core.packages.*)
│   ├── paths.nix         # Path source of truth (hwc.paths.*)
│   ├── polkit.nix (moved to services/polkit)
│   ├── thermal.nix
│   └── validation.nix    # Domain-wide assertions
├── mcp/                  # HWC Infrastructure MCP Server (25 tools, 5 resources)
│   ├── index.nix         # NixOS module, systemd service, Caddy route
│   ├── parts/caddy.nix   # Reverse-proxy route (port 6243 → 6200)
│   └── src/              # TypeScript source (Node.js, MCP SDK)
└── (storage/ and users/ subdirs removed; live config uses flat users.nix
   and mounts.nix at the top level)
```

## Subdomain Notes
- **filesystem.nix** – Creates tmpfiles scaffolding from `hwc.paths.*` plus extra dirs (`hwc.filesystem.structure.dirs` alias).
- **Services** – Backup lives in `domains/data/`, monitoring in `domains/monitoring/`, ntfy/notifications in `domains/notifications/`, networking in `domains/networking/`. Display/login/session policies are in `core/login.nix` under `hwc.system.core.session`.
- **packages.nix** – Core package bundles (base/server/security) under `hwc.system.core.packages.*` (declared in `core/index.nix`, implemented in `core/packages.nix`).
- **users.nix** – Top-level flat file; declares `hwc.system.users.*` and `hwc.system.core.identity.*`.
- **mounts.nix** – Top-level flat file; declares storage-tier mounts (`hwc.system.mounts.*`).
- **mcp/** – HWC Infrastructure MCP Server exposing system/container/network/config state as MCP tools. See `domains/system/mcp/README.md`.

## Usage
- Import `domains/system/index.nix` from machine configs; enable modules via `hwc.system.*` and `hwc.filesystem.*` options.
- Keep home-lane references guarded with `osConfig ? hwc` per the Handshake Protocol when mirrored into `sys.nix` files elsewhere.

## Changelog
- 2026-06-11: `users/` — removed the broken `user.ssh.useSecrets` lane: it did `builtins.readFile` on the `/run/agenix/user-ssh-public-key` runtime path, which can never work in pure eval (agenix decrypts at activation, after evaluation), so `ssh.enable` was unusable. `fallbackKey` renamed to `keys` (public keys are not secrets; they live in the repo). Base role now sets `ssh.enable = true` fleet-wide.
- 2026-06-09: Law 9/10 — converted option-declaring leaf files to directory modules: `mounts/`, `networking/`, `hardware/`, `gpu/`, `usb-automount/`, `users/`, `core/login/` (each `X.nix` → `X/index.nix`, pure git-mv relocation). `mcp/parts/jt.nix` options moved into `mcp/index.nix` (parts/ stays pure). Parity verified via nix-diff (zero behavioral delta).
- 2026-06-09: Law 3 sweep — `mcp/index.nix` no longer hardcodes `/opt/n8n-mcp`, `/opt/business/heartwood-cms`, or `/home/eric/*` sandbox paths; all derive from `hwc.paths.{apps.root,business.root,user.mail,user.home}` with null-safe fallbacks to their prior literals. Server drv hash unchanged (pure refactor).
- 2026-05-22: `networking.nix` — remove `tailscale.funnel` option block and `tailscale-funnel.service` (MCP gateway exposure). Public ingress moved to Cloudflare Tunnel in `domains/networking/cloudflared`. Funnel-on-hostname was creating public DNS records that masked MagicDNS resolution for tailnet clients.
- 2026-05-21: removed orphan dir-style modules superseded by flat top-level files: `core/filesystem.nix`, `core/thermal.nix`, `core/validation.nix`, `core/options.nix`, `core/identity/` (live identity is in `users.nix`), `users/` (live is `users.nix`), `storage/` (no live consumer of `hwc.system.storage.*`), `packages/` (live is `core/packages.nix`). Verified via `rg -n "options\.hwc\.system\.<ns>" -t nix .` (no live consumers outside removed dirs) and full eval (drv hashes unchanged).
- 2026-05-21: removed dead `services/` subtree (backup, hardware, monitoring, ntfy, polkit, protonmail-bridge, protonmail-bridge-cert, shell, vpn + `index.nix`/`options.nix` aggregators). Functionality was migrated to top-level domains (`domains/data/backup/`, `domains/monitoring/`, `domains/notifications/`, etc.) and the system-domain aggregator (`system/index.nix`) no longer imports anything under `services/`. Verified via `rg -ln "domains/system/services|\.\./services|\./services/" -t nix .` (only stale path-header comments remained) and full eval (drv hashes unchanged).
- 2026-05-21: removed `networking/` subdir (orphan; live config is the flat `networking.nix`). Held `samba.nix` which referenced the dead `hwc.infrastructure.samba` namespace plus an unimported `index.nix`/`options.nix` pair. Verified via `nix eval .#nixosConfigurations.{hwc-laptop,hwc-server}.config.system.build.toplevel.drvPath` (drv hashes unchanged from baseline).
- 2026-05-21: `gpu.nix` — fix day-1 hybrid-laptop bug. `nvidia.prime.enable` default changed from `true` to `false` (was forcing PRIME-offload config onto non-existent Intel bus IDs on the server). `environment.sessionVariables` now sets `LIBVA_DRIVER_NAME=iHD` (Intel) and omits `VDPAU_DRIVER` when `prime.enable=true`; pure-NVIDIA hosts (server) still get `LIBVA_DRIVER_NAME=nvidia + VDPAU_DRIVER=nvidia`. Stops poisoning hybrid sessions with NVIDIA VA-API/VDPAU drivers when Intel is the actual renderer
- 2026-05-21: removed `services/session/` (dead since the session lane moved into `core/login.nix` under `hwc.system.core.session`). Was unimported and held a stale copy of the greetd hyprStart script with the same NVIDIA env exports that login.nix had — a real footgun if anyone ever wired it back up
- 2026-05-21: `gpu.nix` — `gpu-launch` and `blender-offload` now `unset __EGL_VENDOR_LIBRARY_FILENAMES` when injecting NVIDIA env. Pairs with the matching `login.nix` change that pins Mesa-only EGL at session start; this lets per-process NVIDIA offload restore full ICD enumeration so blender/games can still use the NVIDIA EGL ICD
- 2026-05-21: `gpu.nix` — reverted the per-process `unset __EGL_VENDOR_LIBRARY_FILENAMES` from `gpu-launch` and `blender-offload`. Companion to the `login.nix` revert (see core/README.md): both were added to address a "WebGL disabled" symptom in LibreWolf that turned out to be a content-process FPP override, not an EGL ICD enumeration problem. The earlier NVIDIA PRIME env strip in `hyprStart` (commit 5c30ef8d) stays — that fix was correct
