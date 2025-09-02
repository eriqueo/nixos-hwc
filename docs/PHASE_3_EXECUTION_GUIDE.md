# PHASE_3_EXECUTION_GUIDE.md — Interface & Toggle Finalization

Goal: profiles orchestrate only; modules implement behind `options.hwc.*`; machines declare facts; Home-Manager reads `nixosConfig` and is only imported under profiles.

## Prerequisites
- Phase 2 complete with clean module boundaries and one-service-per-file.
- Run:
  ./scripts/validate-charter-v4.sh
  nixos-rebuild test --flake .#hwc-laptop

Required result: no violations; test build succeeds.

## 3.1 Wire the HM Boundary (once, under profiles)
- Ensure Home-Manager imports live only under profiles and pass system facts into HM:
  home-manager.extraSpecialArgs = { nixosConfig = config; }
  home-manager.users.<user>.imports = [ ../modules/home/... ]
- No HM module imports at the NixOS top level.

Verification:
  rg "home-manager\.extraSpecialArgs.*nixosConfig\s*=\s*config" profiles/
  rg "modules/home/" --glob '!profiles/**' --glob '!modules/home/**' | wc -l  (must be 0)

## 3.2 Convert Modules to `hwc.*` Options
For each service module (iterate simplest → most complex):
1) Add options:
   options.hwc.services.<name>.enable = lib.mkEnableOption "Enable <name>"
2) Move implementation behind:
   config = lib.mkIf cfg.enable { … }
3) Define any service-specific suboptions under `hwc.services.<name>.*`
4) Prohibit direct `/mnt/*` paths; use `config.hwc.paths.*`

Quick template:
  { config, lib, pkgs, ... }:
  let cfg = config.hwc.services.<name>;
  in {
    options.hwc.services.<name>.enable = lib.mkEnableOption "Enable <name>";
    config = lib.mkIf cfg.enable {
      systemd.services.<name> = { … };
    };
  }

Verification:
  rg "options\.hwc\.services\.<name>\.enable" modules/services/**/<name>.nix
  rg "mkIf cfg\.enable" modules/services/**/<name>.nix
  rg "/mnt/" modules/services/**/<name>.nix | wc -l  (must be 0)

## 3.3 Enforce Profile Purity
- Profiles set toggles and import modules only. No `systemd.`, `virtualisation.`, `services.[^h]`, `environment.`, or `programs.`

Verification:
  rg "systemd\.|virtualisation\.|services\.[^h]|environment\.|programs\." profiles/ | wc -l  (must be 0)

## 3.4 Enforce Machine Purity
- Machines declare hardware facts, paths, and enable toggles; no implementation.

Verification:
  rg "systemd\.|virtualisation\.|environment\.|programs\." machines/ | wc -l  (must be 0)
  rg "hwc\.(gpu|paths|networking|services)\." machines/

## 3.5 Dependency Direction
- No Home → Infrastructure imports; no Infrastructure → Home.
- Layers flow lib → modules → profiles → machines.

Verification:
  rg "modules/home" modules/services/ | wc -l  (must be 0)
  rg "modules/services" modules/home/ | wc -l  (must be 0)

## 3.6 Toggle Matrix (build-time)
Run through these states with `nixos-rebuild test`:
1) All `hwc.services.*.enable = false`
2) Enable each service one at a time; test build after each
3) Enable expected service bundles; test build

Helper:
  nixos-rebuild test --flake .#hwc-MACHINE 2>&1 | tee build-test-MACHINE.log
  rg -i "error|warning" build-test-MACHINE.log

## 3.7 Run Validation Script
  ./scripts/validate-charter-v4.sh
Required result: “No violations found”.

## Completion Criteria (Phase 3)
- HM bridge wired and centralized HM imports in profiles
- Every service behind `options.hwc.*` + `mkIf cfg.enable`
- Profiles/machines pass purity checks
- No `/mnt/*` in repo except via `hwc.paths.*`
- Toggle matrix builds clean
- Validation script reports zero violations
