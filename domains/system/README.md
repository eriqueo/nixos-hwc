# System Domain

## Purpose
- Core OS lane: accounts, networking, filesystem scaffolding, base services, and packages other domains rely on.

## Boundaries
- Namespaces match paths (`hwc.system.*`, `hwc.filesystem.*` shortcut for core/filesystem) per Charter Law 2.
- No Home Manager logic lives here; cross-lane assertions are guarded so the system lane stands alone.

## Structure
```
domains/system/
├── core/                 # See core/README.md for the full listing
│   ├── authentik/        # SSO/Identity Provider (hwc.system.core.authentik.*)
│   ├── login/            # greetd + tuigreet, hyprStart session wrapper
│   ├── coredump.nix      # systemd-coredump retention caps
│   ├── nix-build-limits.nix # nix-daemon MemoryHigh/MemoryMax cgroup ceiling
│   ├── index.nix         # Core aggregator
│   └── packages.nix      # Base/server/security package bundles (hwc.system.core.packages.*)
├── networking/
│   └── index.nix         # SSH, Tailscale, NFS, Samba, firewall, wait-online (hwc.system.networking.*)
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
- 2026-08-29: `mcp/` — `today.ts` and `nightly-review.ts` reworked for the
  notifications CEO information contract and to expose terminal review cases
  (`dc0fce28`, `cd7ab4dd`); `tests/today-ledger.test.ts` updated alongside.
  Detail in `mcp/README.md`.
- 2026-08-28: `core/authentik/` — dead `$PSQL` `CREATE ROLE` + GRANTs in
  `postgresql.postStart` replaced by a declared `ensureUsers` entry with
  `ensureDBOwnership` (`e82ca994`). Detail in `core/authentik/README.md`.
- 2026-08-26: **`core/nix-build-limits.nix` — a nix build took the desktop with
  it, so `nix-daemon` is now capped in bytes** (`1d73dde8`). A local CUDA
  rebuild ran 37 concurrent `cc1plus` at ~800 MB each plus 15 `cicc`/`cudafe++`
  front ends: NixOS ships `max-jobs = auto` (22 here) with `cores = 0` (all 22
  per job), so the real ceiling is 484 compilers, not 22. Anonymous memory hit
  24 GB against 30 GB RAM and the kernel global OOM killer ran for 12 minutes,
  taking a dozen Chromium tabs, `dbus-broker`, both portals, waybar, swaync and
  finally `systemd --user`. Hyprland survived because `session-2.scope` sits
  outside `user@1000.service`, which is why the symptom read as "the bar
  vanished" rather than a compositor crash. Capping `max-jobs`/`cores` was the
  rejected alternative — a job count is a guess at compiler RSS, which ranges
  ~50 MB to ~3 GB, so a cap low enough to survive a CUDA build wastes most
  cores on every ordinary build and still constrains nothing in bytes.
  `MemoryHigh` throttles and forces reclaim so an expensive build slows instead
  of dying; `MemoryMax` is the hard stop and lands the kill inside the build
  cgroup. Expressed as percentages so the laptop and the server share one
  number.
- 2026-08-21: `core/login/` — **`AQ_DRM_DEVICES` tried, then reverted**
  (`36f74438`, reverted by `e3d820f2`). Aquamarine enumerates every DRM card,
  so Hyprland opened the NVIDIA node alongside the Intel one and held it for
  the session; that card has no connectors on this laptop (eDP-1 and every
  DP-\*/HDMI-A-1 hang off i915), so it rendered nothing and pinned the dGPU
  awake at ~11 W of a 27.8 W idle draw. The power config was never at fault —
  `DynamicPowerManagement=2`, `power/control=auto` and `finegrained=true` were
  already correct; the tell was `runtime_suspended_time` reading 0 against 5.5
  days of uptime. The fix did not boot: Hyprland 0.56 aborted in
  `CCompositor::initServer` on both greetd attempts, because Aquamarine rejects
  an unusable value outright rather than falling back to enumeration — a wrong
  value here is an unbootable desktop, not a degraded one. The by-path form is
  the prime suspect (a symlink rather than a real device node) but was never
  confirmed, and `/dev/dri/card1` is untried. The diagnosis and a retry
  procedure survive as a comment; the ~11 W dGPU pin remains open.
- 2026-08-12: `networking/` — Tailscale registration made declarative. New `tailscale.authKeyParameters` option (`ephemeral`/`preauthorized`/`baseURL`), passed through to `services.tailscale`; the wrapper previously dropped it, which made OAuth-client registration inexpressible. Also added a `warnings` entry that fires when `extraUpFlags`/`authKeyParameters` are set while `authKeyFile` is null: upstream gates `tailscaled-autoconnect.service` (the only thing that ever runs `tailscale up`) on `authKeyFile`, so those flags are silently inert without it. That silence is what let hwc-server declare `--advertise-tags=tag:server` for months while actually registering untagged, inheriting the tailnet's 6-month key expiry and dropping off on 2026-08-07. Warn rather than assert: hwc-laptop (`--accept-dns`) and the appliance profile (`--ssh`) carry the same inert flags today and failing their builds is a separate cleanup. Verified red on hwc-laptop before shipping.
- 2026-07-11: usb-automount: mount root now `config.hwc.paths.removableMedia` (default `/mnt`, unchanged) instead of a hardcoded `/mnt` literal (Law 3 migration).
- 2026-07-06: mcp: website tmpfiles/ReadWritePaths repointed to /opt/business/website-site (website eviction).
- 2026-07-06: mcp: hwc_morning_status rewritten as a pure reader of briefing.json (one producer per fact, Doctrine §0.8) — no longer computes health/mail/storage/calendar itself; flags >26h staleness.
- 2026-07-05: Law 12 burn-down — restructured headings to the required contract (`## Purpose` / `## Boundaries` / `## Structure`); content unchanged, headings renamed/split from the old Scope-&-Boundary/Layout form.
- 2026-07-03: `hardware/` — Sensel touchpad fix extended to five layers: new acpid `hwc-sensel-rebind` handler rebinds `i2c_hid_acpi` on lid **open**, covering lid closes that never suspended (waybar lid-toggle in ignore mode), where the layer-4 resume hook never runs and the stale SW_LID=1 kills two-finger scroll. acpid daemon itself is still enabled per-machine (laptop only); the handler is inert where acpid is off.
- 2026-06-11: `hardware/` — new `powerScripts.enable` flag carries the perf-mode/balanced-mode CPU-governor toggle scripts (moved from machines/laptop/config.nix, closing its TODO). Laptop delta is order-only (sorted systemPackages set identical); other machines byte-identical.
- 2026-06-11: `core/` — new `hwc.system.core.nixld.guiLibs.enable` flag carries the X11/GTK/audio nix-ld library set; desktop and gaming roles flip it instead of duplicating the 22-package list. All 5 toplevels byte-identical (proven no-op).
- 2026-06-11: `gpu/` — CUDA binary cache (cache.nixos-cuda.org substituter + key) moved here from machines/{laptop,server}/config.nix duplication; applies to any machine with `gpu.type = "nvidia"`. nix-diff: delta is nix.conf only (substituter sets unchanged per machine).
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
