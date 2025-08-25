# nixos-hwc/modules/home/productivity.nix
#
# HOME: Productivity apps (Obsidian, Firefox, LibreOffice, Thunderbird)
# Pure Home-Manager module; no home-manager.users.* here.
#
# DEPENDENCIES (Upstream):
#   - nixpkgs allowUnfree for Obsidian if used
#
# USED BY (Downstream):
#   - profiles/workstation.nix (enables toggles)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: ../modules/home/productivity.nix
#
# USAGE (from profile/machine):
#   hwc.home.productivity = {
#     enable = true;
#     notes.obsidian = true;
#     browsers.firefox = true;
#     office.libreoffice = true;
#     communication.thunderbird = true;  # requires a profiles entry; provided below
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.productivity;
  t   = lib.types;
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.home.productivity = {
    enable = lib.mkEnableOption "Enable productivity app bundle";

    notes.obsidian = lib.mkOption {
      type = t.bool; default = false;
      description = "Install Obsidian (unfree).";
    };

    browsers.firefox = lib.mkOption {
      type = t.bool; default = false;
      description = "Enable Firefox via Home Manager.";
    };

    office.libreoffice = lib.mkOption {
      type = t.bool; default = false;
      description = "Install LibreOffice.";
    };

    communication.thunderbird = lib.mkOption {
      type = t.bool; default = false;
      description = "Enable Thunderbird with a default profile.";
    };
  };

  #============================================================================
  # IMPLEMENTATION (Home-Manager scope)
  #============================================================================
  config = lib.mkIf cfg.enable {

    # Packages controlled by simple toggles
    home.packages =
      (lib.optional cfg.notes.obsidian pkgs.obsidian)
      ++ (lib.optional cfg.office.libreoffice pkgs.libreoffice);

    # Firefox (Home Manager module)
    programs.firefox.enable = lib.mkIf cfg.browsers.firefox true;

    # Thunderbird (Home Manager module) — add a minimal required profile
    programs.thunderbird = lib.mkIf cfg.communication.thunderbird {
      enable = true;

      # Provide at least one profile or HM will error.
      profiles.default = {
        isDefault = true;
        # You can add `settings = { ... };` or `userChrome = ''...'';` later.
      };
    };
  };
}
