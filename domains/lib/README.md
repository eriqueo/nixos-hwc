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

- 2026-03-04: Extracted from `domains/server/containers/_shared/` (Phase 2 of DDD migration)
