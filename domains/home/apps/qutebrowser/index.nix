# domains/home/apps/qutebrowser/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.qutebrowser;
  package = if cfg.package != null then cfg.package else pkgs.qutebrowser;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.qutebrowser = {
    enable = lib.mkEnableOption "Qutebrowser keyboard-focused browser";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Package to use for qutebrowser.";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional packages to install alongside qutebrowser.";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ package ] ++ cfg.extraPackages;

    # TODO: Add application-specific configuration
    # Examples:
    # - xdg.configFile for config files
    # - xdg.desktopEntries for custom launchers
    # - Theme integration with config.hwc.home.theme

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = cfg.package != null || (pkgs ? qutebrowser);
        message = "Package qutebrowser not found in nixpkgs and no custom package provided";
      }
    ];
  };
}