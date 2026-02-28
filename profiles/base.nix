# nixos-hwc/profiles/base.nix
#
# Base System Profile (Orchestration Only)
# Aggregates foundational modules and sets high-level defaults.
# No hardware driver details; no workstation-specific toggles here.

{ lib, pkgs, ... }:

{
  #==========================================================================
  # IMPORTS – Foundational system modules (single root orchestrator)
  #==========================================================================
  imports = [
    ../domains/system/index.nix
    # Infrastructure domain migrated to system/ per Charter v10.4
  ];

  #==========================================================================
  # BASE SETTINGS – Cross-cutting defaults (machines may override)
  #==========================================================================


  #==========================================================================
  # NETWORKING (orchestration only; implementation lives in modules/system/*)
  #==========================================================================
  

  #==========================================================================
  # CORE SYSTEM DEFAULTS
  #==========================================================================

}
