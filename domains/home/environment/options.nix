# domains/home/environment/options.nix
#
# Consolidated options for home environment subdomain
# Charter-compliant: ALL environment options defined here

{ lib, ... }:

let
  t = lib.types;
in
{
  #============================================================================
  # DEVELOPMENT OPTIONS
  #============================================================================
  options.hwc.home.development = {
    enable = lib.mkEnableOption "Development tools and environment";

    #==========================================================================
    # EDITORS
    #==========================================================================
    editors = {
      neovim = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Enable Neovim with configuration";
      };

      micro = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Enable Micro editor";
      };
    };

    #==========================================================================
    # LANGUAGE TOOLCHAINS
    #==========================================================================
    languages = {
      nix = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Enable Nix development tools";
      };

      python = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Enable Python development tools";
      };

      javascript = lib.mkOption {
        type = t.bool;
        default = false;
        description = "Enable JavaScript/Node.js development tools";
      };

      rust = lib.mkOption {
        type = t.bool;
        default = false;
        description = "Enable Rust development tools";
      };
    };

    #==========================================================================
    # TOOLING
    #==========================================================================
    containers = lib.mkOption {
      type = t.bool;
      default = true;
      description = "Enable container development tools";
    };

    directoryStructure = lib.mkOption {
      type = t.bool;
      default = true;
      description = "Create development directory structure";
    };
  };

  #============================================================================
  # PRODUCTIVITY OPTIONS
  #============================================================================
  options.hwc.home.productivity = {
    enable = lib.mkEnableOption "Productivity tooling via Home Manager";

    notes.obsidian = lib.mkOption {
      type = t.bool;
      default = false;
      description = "Install Obsidian (unfree)";
    };

    browsers.firefox = lib.mkOption {
      type = t.bool;
      default = false;
      description = "Enable Firefox via Home Manager";
    };

    office.libreoffice = lib.mkOption {
      type = t.bool;
      default = false;
      description = "Install LibreOffice";
    };

    communication.thunderbird = lib.mkOption {
      type = t.bool;
      default = false;
      description = "Enable Thunderbird via Home Manager";
    };

    extraPackages = lib.mkOption {
      type = t.listOf t.package;
      default = [ ];
      description = "Additional user-scoped packages to include";
    };
  };
}