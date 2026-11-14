# herdr-core

## Purpose
Installs the Herdr core (`herdr-core`, also `hc`), the terminal runtime behind the Herdr App, pinned from its upstream release. On a headless host, `serve` keeps one core running across reboots, so the laptop's Herdr machine entry reaches terminals there without a login.

## Boundaries
- ✅ Manages: the pinned `herdr-core` package (with `hc`) on `home.packages`; the `herdr-core.service` user unit when `serve.enable` is set.
- ❌ Does not manage: the older TUI multiplexer `herdr` and its agent status hooks (→ `apps/herdr`); the Herdr App on the laptop (an unmanaged trial in `~/.local`); tracker links in Herdr terminals (→ `apps/agent-harness`, which points `TRACKER_HC_BIN` here when this module is on).
- ❌ Not `apps/herdr`: that module ships a different project (`ogulcancelik/herdr` 0.8.2) on every machine. Its version, binary and options would all be shared with an unrelated product.

## Structure
- `index.nix` — options (`enable`, `package`, `serve.enable`, `serve.binary`), the package, the `herdr-core` user unit (zsh start for the login PATH, `KillMode=process`, start limit 5 in 120 s), the `herdr-core-reclaim` ExecStartPre helper, and the assertions. Managed (servers): `package`, `default.target`, `Restart=always`, reclaim. `serve.binary` (laptop): the app's `~/.local/bin/herdr-core`, no package, `graphical-session.target`, `Restart=on-failure`, no reclaim.
- `parts/package.nix` — the static `herdr-core-linux-x86_64` release tarball from `releases.herdr.dev/core/<version>/` with its manifest sha256; installs `bin/herdr-core` and the `bin/hc` link.

## Operating rules
- Update by bumping `parts/package.nix` (version + hash from `releases.herdr.dev/core/<version>/manifest.json`), then deploy. Never run `hc machine update hwc-home|hwc-work` from the laptop or `hc update` on a server: either would put an unmanaged copy in `~/.local/bin` and move the core out of this unit.
- `hc server restart` on a server moves the core into a transient `hc-serve-*` unit and this unit exits 0; terminals keep running. The unit restarts 5 s later and its reclaim step stops that transient core (default session only; other `HC_SESSION` cores stay), so the unit owns the core again. `hc server stop` is undone the same way; `systemctl --user stop herdr-core` keeps it down.
- The laptop's unit only starts a core when none runs (a second `serve` exits 0 at once); the Herdr App attaches to whichever core answers. It never takes the core back from the app, so an app core update leaves it in the app's transient unit until the next login.
- `systemctl --user restart herdr-core` keeps terminals; the laptop's machine connection comes back by itself.

## Changelog
- 2026-11-14: `serve.binary`: the laptop runs the Herdr App's own `~/.local/bin/herdr-core` at graphical login (no package), so a reboot's terminals and agents come back before the app opens. Managed servers restart always and reclaim the default core from a transient `hc-serve-*` unit after `hc server restart`, replacing the manual stop/start. agent-harness keeps `TRACKER_HC_BIN` on `~/.local/bin/hc` where `serve.binary` is set.
- 2026-11-13: Added. Pinned 0.1.20 (the binary the hand-installed trial ran, sha256 identical). `serve` enabled on hwc-home and hwc-work, replacing the transient `hc-serve-*` cores and `~/.local/bin/herdr-core` copies there.
