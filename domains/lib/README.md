# lib/ — Pure Container Helpers

## Purpose

Domain-independent pure helper functions for building OCI container definitions.
These are **not** NixOS modules — they are plain functions that take `{ lib, pkgs }` and return attribute sets.

Extracted from `domains/server/containers/_shared/` during DDD migration so that
any domain (media, networking, data, etc.) can use them without depending on the server domain.

## Boundaries

- **Pure functions only**: No `config` access, no NixOS module boilerplate
- **Container definitions only**: No systemd services in mkContainer (mkInfraContainer has them as they're integral to infrastructure containers)
- **Domain-independent**: No assumptions about which domain imports these

## Structure

```
lib/
├── README.md              # This file
├── mkContainer.nix        # Application containers (media apps, *arr services)
├── mkInfraContainer.nix   # Infrastructure containers (gluetun, pihole)
└── arr-config.nix         # *arr-specific config.xml enforcement
```

## Usage

```nix
{ lib, pkgs, ... }:
let
  helpers = import ../../../../lib/mkContainer.nix { inherit lib pkgs; };
  inherit (helpers) mkContainer;
in
{
  config = lib.mkIf cfg.enable (mkContainer {
    name = "sonarr";
    image = cfg.image;
    # ...
  });
}
```

## Backwards Compatibility

During migration, `domains/server/containers/_shared/{pure,infra,arr-config}.nix`
re-export from these canonical files. Existing imports continue to work.

## Changelog
- 2026-08-12: `hm.nix` gained `fleet osConfig` → `{ ips, fqdn }`, reading `hwc.networking.hosts` on NixOS hosts with literal fallbacks for standalone HM (Law 1 forbids assuming `osConfig`). Per decision 3 of `workspace/plans/2026-06-11-registry-magic-strings.md`, this file is deliberately the **single HM-lane copy** of the fleet's tailnet addresses — the system lane's copy is the registry's own option defaults. Two producers, one per lane, both greppable; the alternative was the status quo of one copy per consumer, which is what let a single hwc-server re-registration break four files at once on 2026-08-12. First consumers: `domains/home/core/shell/index.nix` and its `parts/aliases.nix`.
- 2026-08-06: `mkSimpleApp.nix` gained the `HWC-EXCEPTION(Law 10)` annotation it always warranted — it is a module FACTORY, so the `mkEnableOption` it builds belongs to the caller's `domains/home/apps/<name>/index.nix`, which declares it by calling with its own folder name. Same exception class as `domains/paths/paths.nix`. Not new debt: the old Law 10 lint never saw this file at all, because `mkEnableOption` does not contain the substring `mkOption`. The corrected v12.6 check matches both constructors and honors §4 annotations.
- 2026-07-05: Law 5 burn-down — added `HWC-EXCEPTION(Law 5)` annotation blocks (reason/justification/plan/revocable) to this domain's raw `oci-containers` module(s); infra-shaped containers are sanctioned exceptions to the mkContainer rule. Comments only, no behavior change.

- 2026-06-11: Add mkSimpleApp.nix (one-package HM app modules) and hm.nix
  (cross-lane helpers: isNixOSHost, osCfgOr, sysLaneAssert).

- 2026-03-04: Extracted from `domains/server/containers/_shared/` (Phase 2 of DDD migration)
