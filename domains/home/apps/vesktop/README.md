# vesktop

## Purpose

Installs Vesktop, an alternate Discord desktop client with Vencord built in,
through Home Manager's native `programs.vesktop` module.

## Boundaries

- ✅ Manages `hwc.home.apps.vesktop.enable` and delegates installation to `programs.vesktop`.
- ✅ Owns the `vesktop` command, desktop entry, and login autostart file so every launch runs through `gpu-integrated`.
- ❌ Does not manage Discord credentials, account state, plugins, or Vesktop settings.
- ❌ Does not install the official unfree `pkgs.discord` client.

## Structure

- `index.nix` — HWC enable option, native Home Manager Vesktop integration, and the integrated-GPU launcher.

## Changelog

- 2026-09-16: Route every Vesktop launch through `gpu-integrated`. Vesktop's GPU
  process held the NVIDIA device open for a full session and kept the dGPU at
  ~15 W idle. The module now owns `bin/vesktop`, the desktop entry, and
  `~/.config/autostart/vesktop.desktop` (Vesktop's own copy called electron by
  store path and bypassed any wrapper).

- 2026-09-14: Added the Vesktop module and enabled it for hwc-laptop.
