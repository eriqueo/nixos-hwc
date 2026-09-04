# hwc.home.apps.t3code

**T3 Code** — an agent-harness control plane. It drives the provider CLIs
already on this machine from one window, and from the T3 Code phone app over the
same server. Upstream is `pingdotgg/t3code`; both machines run Eric's fork
`eriqueo/t3code`, checked out at `~/600_apps/t3code`.

Two shapes, one module:

| Shape | Machine | What runs | Reached by |
|---|---|---|---|
| `desktop.*` | hwc-laptop | Electron app, which starts its own backend | the window; phone over Tailscale Serve |
| `serve.*` | hwc-server | `t3 serve`, headless, on `127.0.0.1:3773` | `https://t3.hwc.iheartwoodcraft.com` via Caddy |

They are **mutually exclusive per machine**, enforced by an assertion — see the
design note below.

## Structure

```
index.nix   # hwc.home.apps.t3code — desktop launcher + Electron shim + desktop
            #   entry; headless t3-serve unit; t3-update
README.md   # this file
```

There is no `parts/`. This module packages no source.

## Design decisions

- **Nix packages nothing; the working tree owns the build.** T3 Code is a pnpm
  monorepo with an Electron app, a server, a web client and a mobile client.
  Packaging it as a derivation would mean vendoring a lockfile hash and
  rebuilding the whole tree on every upstream pull. Eric forked the repository
  in order to change it, so the working tree is the point. The launcher runs
  `apps/desktop/dist-electron/main.cjs` out of `cfg.repo` and prints the exact
  build commands when that file is missing.

- **Electron comes from nixpkgs, through `ELECTRON_OVERRIDE_DIST_PATH`.** The
  Electron binary npm downloads expects an FHS dynamic linker and cannot run on
  NixOS. The `electron` npm package reads `ELECTRON_OVERRIDE_DIST_PATH` and
  joins it with `path.txt`, so a directory holding one symlink named `electron`
  is the whole adapter. Verified 2026-08-26: the fork pins Electron 41.5.0,
  nixpkgs carries 41.9.1, and the app reported `backend ready` and
  `main window created`.

- **The shim is rebuilt at every start, never baked in.** Writing
  `/nix/store/…-electron-41.9.1/bin/electron` into the launcher would work until
  the next `nix-collect-garbage` deleted it, and then fail with a
  file-not-found the user cannot act on. The launcher resolves
  `command -v electron` instead, and `electronPackage` sits in `home.packages`
  so the store path is a GC root.

- **The icon is an out-of-store symlink.** `assets/prod/logo.svg` lives in the
  fork's working tree, outside this flake. A plain `source` would ask the pure
  evaluator to import a path it cannot see. `mkOutOfStoreSymlink` is the
  Home Manager idiom for exactly that case.

- **The autostart service starts the APP, not a second server.**
  `apps/desktop/src/app/DesktopApp.ts:79` always starts its own backend: it
  probes upward for a free port and never attaches to a running one. A separate
  `t3 serve` unit against the same `~/.t3` would put two writers on one
  event-sourced SQLite store. Starting the app itself keeps one backend, one
  database and one thread history, and still gives the always-running behaviour
  a service is wanted for.

- **`port` is set, and Tailscale Serve is not.** `T3CODE_PORT` reaches the
  desktop backend and fixes its port — measured 2026-08-26 with `T3CODE_PORT=3891`,
  which produced `baseUrl: http://127.0.0.1:3891/`. A fixed port matters because
  the phone app's pairing does not survive a moving port number.
  `T3CODE_TAILSCALE_SERVE` is stripped on the way down, and that is upstream's
  deliberate choice. `rg -c T3CODE_TAILSCALE_SERVE apps packages scripts`
  returns exactly two files. One reads it — the headless `t3 serve` CLI at
  `apps/server/src/cli/config.ts:134`. The other deletes it:
  `DESKTOP_BACKEND_ENV_NAMES`
  (`apps/desktop/src/backend/DesktopBackendConfiguration.ts:77`) feeds
  `backendChildEnvPatch`, which maps every name in that list to `undefined` and
  strips it from the backend child's environment. The desktop app supplies its
  own exposure settings instead, over `desktop:set-server-exposure-mode` and
  `desktop:set-tailscale-serve-enabled` (`apps/desktop/src/ipc/channels.ts:38`).
  Measured: the launcher exported the variable, the app started, and
  `tailscale serve status` still said `No serve config`.
  **Turn Tailscale Serve on in Settings → Connections.**

- **The two shapes cannot share a machine, and an assertion says so.** The
  desktop app always starts its own backend and never attaches to a running one,
  so `desktop.enable` and `serve.enable` together put two writers on one
  event-sourced `~/.t3` store. That is not a theoretical risk: it is the failure
  measured on 2026-08-26, which surfaced as `Primary environment request failed
  during fetch-session-state (HTTP 500)`. The assertion fails the build instead.

- **The headless unit does NOT carry the desktop unit's `pkill` sweep.** That
  sweep exists because Electron moves the backend it spawns into a sibling
  systemd scope, outside the unit's cgroup. `t3 serve` is the process systemd
  starts, so it stays in the unit's own cgroup and `KillMode=control-group`
  reaches it. Copying the sweep across would have been cargo cult, and worse than
  useless: the pattern matches `apps/server/dist/bin.mjs`, which is the headless
  server's own command line.

- **`serve` gets an explicit PATH, because a user unit inherits none.** T3
  resolves provider binaries out of its own process environment. On hwc-server
  `claude` is an ad-hoc npm global (`~/.npm-global/bin`) while `codex`, `pi` and
  `herdr` come from `/etc/profiles/per-user/eric/bin` — none of which reaches a
  systemd user service by itself. `serve.packages` supplies the Nix half and
  `serve.extraPath` the non-store half. `pi` earns its place alongside the
  others: the `delegate` skill runs `pi --model mycloud/dx1` as a **child
  process** and strips every `HERDR_*` variable
  (`~/.claude/skills/delegate/scripts/delegate.py:102`), so cross-provider
  delegation needs the binary on PATH, not a Herdr pane.

- **`~/.t3/userdata` is CRITICAL and is in Borg.** It holds the event-sourced
  SQLite store plus the server signing key; losing the key invalidates every
  paired client and the store is regenerable from nothing. `~/.t3/caches` and
  `~/.t3/worktrees` are REPLACEABLE and stay out. The copy is taken live, so stop
  `t3-serve.service` before a run whose restore must be certain.

## Rebuilding after a pull

```
t3-update
```

One command, because the three steps are not independent: the server bundle
**embeds** the web client (`apps/server/vite.config.ts` declares
`dependsOn: ["@t3tools/web#build"]` and the build lands in
`apps/server/dist/client`), so a pull without a rebuild leaves source, bundle and
client assets on different revisions. On a `serve` machine `t3-update` also
restarts `t3-serve.service`; on a `desktop` machine it does not touch the running
app.

No `hms` is needed for a pull — the launchers read the working tree at run time.
Run `hms` only after changing `desktop.electronPackage`, `repo`, the desktop
entry, or anything under `serve.*`.

**Warning: keep `desktop.electronPackage` on the same MAJOR version as
`apps/desktop/package.json`.** `main.cjs` is compiled against that Electron ABI.

## Pairing the headless server

The pairing URL and QR that `t3 serve` prints at startup are **loopback** URLs
(`apps/server/src/startupAccess.ts` derives them from the bind host) and are
useless from a phone. Mint one against the public hostname instead:

```
ssh hwc-server 't3-serve --help'   # flags, if needed
ssh hwc-server 'cd ~/600_apps/t3code && node apps/server/dist/bin.mjs \
  auth pairing create --base-url https://t3.hwc.iheartwoodcraft.com'
```

`--base-url` is a real flag (`apps/server/src/cli/auth.ts:74`).

## Related

`t3` (`~/.local/bin/t3`) runs the same fork's SERVER without Electron on the
laptop, for ad-hoc headless use. That script is hand-installed and is not managed
here; on hwc-server the `serve` shape of this module supersedes it.

## Changelog

- 2026-09-03: **Split into two shapes so hwc-server can run the same harness
  headless.** Options moved under `desktop.*` (`electronPackage`, `port`,
  `autoStart`, `desktopEntry`) and a new `serve.*` block added
  (`enable`/`host`/`port`/`packages`/`extraPath`), driving a `t3-serve.service`
  user unit on `default.target`. `profiles/desktop/home.nix` moved to the new
  names; `machines/server/home.nix` enables `serve` with `desktop.enable = false`.
  The reachability half lives in `domains/networking/routes.nix` (`t3` vhost →
  `127.0.0.1:3773`), which is what lets the phone use the harness while the
  laptop is off. Also new: `t3-update`, one command for pull + install + build +
  restart, because the server bundle embeds the web client and the three steps
  cannot drift apart safely. Design notes above record what the adversarial
  review caught before the build: the loopback pairing URL, the PATH a user unit
  does not inherit, and the `pkill` sweep that must NOT be copied.
- 2026-09-03: `electronPackage` default moved from `pkgs.electron` to
  `pkgs.electron_43`, following the fork's rebase onto upstream
  `pingdotgg/t3code` main. The desktop app's pin went 41.5.0 -> 43.4.1, and
  `main.cjs` is compiled against that ABI, so the floating `pkgs.electron`
  (41.9.1) would no longer run it. Pinned to the MAJOR attribute now rather
  than the floating alias, so a nixpkgs bump cannot move the ABI on its own.
  The rebase is what makes Claude Fable 5.1 selectable: upstream moved model
  slugs out of `ClaudeProvider.ts` and into `model-manifest.json`, which
  carries `claude-fable-5-1`. The old checkout hardcoded `claude-fable-5`.
- 2026-08-26: Fixed an orphaned-backend leak the autostart service caused.
  Electron moves the backend it spawns into a sibling systemd scope
  (`…/app.slice/app-electron-<pid>.scope`), so `systemctl --user stop t3code`
  killed the app and left the backend alive holding port 3773. The next launch
  started a SECOND backend on the same `~/.t3` store, and the app failed with
  `Primary environment request failed during fetch-session-state (HTTP 500)`.
  The unit now sweeps by command line in `ExecStartPre` and `ExecStopPost`,
  because systemd's own `KillMode` cannot reach a process outside the unit's
  cgroup. Verified: stop leaves 0 backends and frees the port; start gives
  exactly 1 backend, 1 window and `HTTP 200`.
- 2026-08-26: Added `port` (default 3773 in the desktop profile) and
  `autoStart` (systemd user service on `graphical-session.target`). A
  `tailscaleServe` option was built, measured to do nothing, and removed rather
  than shipped — see the design note above.
- 2026-08-26: Created. Launcher + nixpkgs Electron shim + desktop entry;
  enabled in `profiles/desktop/home.nix`. Verified live: `t3code` reached
  `backend ready` and `main window created`.
