{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps.qutebrowser;
  package = if cfg.package != null then cfg.package else pkgs.qutebrowser;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

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
