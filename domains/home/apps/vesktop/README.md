# vesktop

## Purpose

Installs Vesktop, an alternate Discord desktop client with Vencord built in,
through Home Manager's native `programs.vesktop` module.

## Boundaries

- ✅ Manages `hwc.home.apps.vesktop.enable` and delegates installation to `programs.vesktop`.
- ❌ Does not manage Discord credentials, account state, plugins, or Vesktop settings.
- ❌ Does not install the official unfree `pkgs.discord` client.

## Structure

- `index.nix` — HWC enable option and native Home Manager Vesktop integration.

## Changelog

- 2026-09-14: Added the Vesktop module and enabled it for hwc-laptop.
