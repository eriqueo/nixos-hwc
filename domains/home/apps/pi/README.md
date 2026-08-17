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
- **Endpoint = the LiteLLM proxy, not the pod.** `dx1.baseUrl` is
  `https://dx1.datax.to/v1`. This is the same client-side entry point the
  DataX app uses; it survives DX1 moving between RunPod pods. Pointing at a
  pod-proxy URL directly is what broke this module once already (see
  changelog), so a `proxy.runpod.net` baseUrl now raises a warning.
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

- 2026-08-16: `dx1.baseUrl` → `https://dx1.datax.to/v1` (LiteLLM proxy). The
  pod-proxy URL for `eanzbnhtt3ji8t` went dead when RunPod flagged a critical
  host error on that machine and DX1 migrated to an H100 pod on 2026-07-22;
  every pi request had been 404ing since. Verified against the new URL with
  the agenix key: `GET /v1/models` → 200 (`llm`, `dx1`), `POST
  /v1/chat/completions` → 200. Warning text generalized off the dead pod id.
- 2026-07-17: Created. Pinned v0.80.7; `mycloud`/`dx1` defaults (256k ctx /
  64k out, from lil-box); agenix-backed apiKey via `!cat` indirection; enabled
  fleet-wide in profiles/base/home.nix. `dx1.baseUrl` set to the RunPod
  pod-proxy URL for pod `eanzbnhtt3ji8t`. models.json immutable; settings.json
  seeded-writable (tuxedo pattern) so pi can persist its own runtime state.
