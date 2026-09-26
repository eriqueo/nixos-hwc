# bitwarden

## Purpose
Installs the Bitwarden desktop client for the self-hosted Vaultwarden account.

## Boundaries
- Manages `hwc.home.apps.bitwarden.enable` and the desktop package.
- The client owns its writable settings and credentials. Set its self-hosted server to `https://vaultwarden.hwc.iheartwoodcraft.com` at login.

## Structure
- `index.nix` — one-package Home Manager module using `mkSimpleApp`.

## Changelog
- 2026-09-26: Added the desktop client for the existing Vaultwarden service.
