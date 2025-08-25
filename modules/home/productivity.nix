# nixos-hwc/modules/home/productivity.nix
#
# Home UI: Productivity stack (HM consumer via NixOS orchestrator)
# NixOS options gate inclusion; Home‑Manager config lives under home-manager.users.<user>.
#
# DEPENDENCIES (Upstream):
#   - profiles/workstation.nix (activates HM; sets home.stateVersion)
#   - home-manager.nixosModules.home-manager
#
# USED BY (Downstream):
#   - machines/*/config.nix (e.g., hwc.home.productivity.* toggles)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix (top-level imports list)
#
# USAGE EXAMPLE (in workstation.nix):
#   hwc.home.productivity = {
#     enable = true;
#     notes.obsidian = true;
#     browsers.firefox = true;
#     office.libreoffice = true;
#     communication.thunderbird = true;
#   };

{ config, lib, pkgs, ... }:

let
  t   = lib.types;
  cfg = config.hwc.home.productivity;
in
{
  #============================================================================
  # OPTIONS (NixOS layer)
  #============================================================================
  options.hwc.home.productivity = {
    enable = lib.mkEnableOption "Productivity tooling via Home‑Manager";

    notes.obsidian = lib.mkOption {
      type = t.bool;
      default = false;
      description = "Install Obsidian (unfree).";
    };

    browsers.firefox = lib.mkOption {
      type = t.bool;
      default = false;
      description = "Enable Firefox via Home‑Manager.";
    };

    office.libreoffice = lib.mkOption {
      type = t.bool;
      default = false;
      description = "Install LibreOffice.";
    };

    communication.thunderbird = lib.mkOption {
      type = t.bool;
      default = false;
      description = "Enable Thunderbird via Home‑Manager.";
    };

    extraPackages = lib.mkOption {
      type = t.listOf t.package;
      default = [ ];
      description = "Additional user‑scoped packages to include.";
    };
  };

  #============================================================================
  # IMPLEMENTATION (NixOS -> HM bridge)
  #============================================================================
  config = lib.mkIf cfg.enable {

    home-manager.useGlobalPkgs = lib.mkDefault true;

    home-manager.users.eric = { ... }: let
      pkgsList =
        (lib.optionals cfg.notes.obsidian        [ pkgs.obsidian ]) ++
        (lib.optionals cfg.office.libreoffice    [ pkgs.libreoffice ]) ++
        cfg.extraPackages;
    in {
      # HM: packages/env
      home.packages = pkgsList;

      # HM: browsers / mail
      programs.firefox.enable    = cfg.browsers.firefox;
      #programs.thunderbird.enable = cfg.communication.thunderbird;

      # HM housekeeping (can be set globally; safe default here)
      home.stateVersion = lib.mkDefault "24.05";
    };
  };
}
