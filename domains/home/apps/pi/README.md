# hwc.home.apps.pi

pi coding agent (`@earendil-works/pi-coding-agent`) pinned at **v0.80.7**,
wired to DataX's **DX1** model as the `mycloud` provider. Declarative
replacement for the imperative `setup-pi.sh` install on datax-box
(`/home/projects/bin/pi` + hand-written `~/.pi/agent/*.json` + `.bashrc` PATH
edits).

## Structure

```
index.nix          # hwc.home.apps.pi — options + models.json/settings.json rendering
parts/package.nix  # pinned buildNpmPackage of the pi monorepo (vendored from
                   # nixpkgs; hwc-server's stable channel has no pi-coding-agent)
```

## Design decisions

- **Split config (immutable models / seeded settings).**
  `models.json` is a `home.file` store symlink — deterministic provider config,
  byte-identical across hosts, and pi never writes it. `settings.json` is
  **seeded then mutable** via `home.activation` (the tuxedo/freecad
  copy-if-absent pattern): pi rewrites it at runtime (`lastChangelogVersion`,
  trust decisions, UI prefs), so a store symlink would re-nag the changelog
  every launch and drop trust state. Nix provides the initial
  `defaultProvider`/`defaultModel`; pi owns it thereafter.
- **Secret never in the store.** `models.json` uses pi's shell-command
  indirection — `"apiKey": "!cat /run/agenix/pi-dx1-api-key"` — resolved at
  request time. The key lives in
  `domains/secrets/parts/home/pi-dx1-api-key.age` (default mount
  root:secrets 0440; eric reads via the `secrets` group).
- **Endpoint = RunPod pod proxy.** `dx1.baseUrl` points at pod
  `eanzbnhtt3ji8t` ("DX1 on RTX6000"). The pod-proxy URL is stable across
  Stop/Start (pod ID persists) and only changes on terminate+recreate — at
  which point it's a one-line `dx1.baseUrl` bump + rebuild. Not a serverless
  endpoint (none exists); DX1 runs as this single persistent pod.
- **Vendored package, not overridden.** hwc-server rides nixpkgs-stable
  (25.11) which lacks `pi-coding-agent`, so parts/package.nix carries the
  full derivation (based on nixpkgs' 0.80.2 expression, bumped to 0.80.7).

## Updating pi

```
nix flake prefetch github:earendil-works/pi/vX.Y.Z        # → src.hash
curl -sLO https://raw.githubusercontent.com/earendil-works/pi/vX.Y.Z/package-lock.json
nix run nixpkgs#prefetch-npm-deps -- ./package-lock.json  # → npmDepsHash
```
Bump `version` + both hashes in `parts/package.nix`.

## Changelog

- 2026-07-17: Created. Pinned v0.80.7; `mycloud`/`dx1` defaults (256k ctx /
  64k out, from lil-box); agenix-backed apiKey via `!cat` indirection; enabled
  fleet-wide in profiles/base/home.nix. `dx1.baseUrl` set to the RunPod
  pod-proxy URL for pod `eanzbnhtt3ji8t`. models.json immutable; settings.json
  seeded-writable (tuxedo pattern) so pi can persist its own runtime state.
