# profiles/ — the role layer

## Purpose

A **role** is a named bundle of `hwc.*` option flips and domain imports —
nothing else. Machines compose roles via the `machines` registry in
`flake.nix`; profiles never reference machines and roles never import roles.

## Contract (Charter Law 16)

- One folder per role, containing lane halves named `sys.nix` (NixOS lane)
  and/or `home.nix` (Home Manager lane). A half with nothing to say does
  not exist; the flake resolver silently skips missing halves.
- Halves contain ONLY option assignments (`mkDefault` for anything a
  machine may override) and domain imports. Forbidden: `mkDerivation`,
  `fetchurl`, `writeShellScript*`, inline `systemd.services` bodies, option
  declarations, machine hostnames.
- `home.nix` halves obey Law 1: they evaluate with `osConfig = {}` and are
  OS-agnostic by design.
- Machine membership lives ONLY in the `flake.nix` machines table.

## Structure

```
base/        sys.nix  home.nix    # every machine — system core, secrets, CLI env
desktop/     sys.nix  home.nix    # laptop, xps — screen + human (GUI apps, mail client menu)
server/      sys.nix              # server, xps — infra serving (Phase C)
business/    sys.nix              # server — Heartwood operations (Phase C)
monitoring/  sys.nix              # server, xps — observability
gaming/      sys.nix              # kids — retro gaming station
appliance/   sys.nix              # firestick — lean travel TV stack
mail/        home.nix             # server — hwc.mail menu (Phase C)
```

## Changelog

- 2026-06-11: Phase B — machine membership moved to the flake.nix machines
  registry; HM bootstrap moved from desktop/sys.nix into flake glue.
- 2026-06-10: Phase A — profiles restructured from flat files
  (core/session/home-session/monitoring/gaming/firestick) into role folders
  with sys/home lane halves.
