# hwc.home.apps.t3code

**T3 Code** — an agent-harness control plane. It drives the provider CLIs
already on this machine from one desktop window, and from the T3 Code phone app
over the same server. Upstream is `pingdotgg/t3code`; this machine runs Eric's
fork `eriqueo/t3code`, checked out at `~/600_apps/t3code`.

## Structure

```
index.nix   # hwc.home.apps.t3code — launcher, Electron shim, desktop entry
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

## Rebuilding after a pull

```
cd ~/600_apps/t3code
npx --yes pnpm@11.10.0 install
npx --yes pnpm@11.10.0 build
```

No `hms` is needed — the launcher reads the working tree at run time. Run `hms`
only after changing `electronPackage`, `repo`, or the desktop entry.

**Warning: keep `electronPackage` on the same MAJOR version as
`apps/desktop/package.json`.** `main.cjs` is compiled against that Electron ABI.

## Related

`t3` (`~/.local/bin/t3`) runs the same fork's SERVER without Electron, for
headless use and for pairing the phone app. That script is hand-installed and
is not managed here.

## Changelog

- 2026-08-26: Created. Launcher + nixpkgs Electron shim + desktop entry;
  enabled in `profiles/desktop/home.nix`. Verified live: `t3code` reached
  `backend ready` and `main window created`.
