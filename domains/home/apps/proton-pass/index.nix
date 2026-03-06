# domains/home/apps/proton-pass/index.nix
{ lib, pkgs, config, ... }:
let
  cfg = config.hwc.home.apps.proton-pass;

  behavior   = import ./parts/behavior.nix   { inherit lib pkgs config; };
  appearance = import ./parts/appearance.nix { inherit lib pkgs config; };
  session    = import ./parts/session.nix    { inherit lib pkgs config; };

  homeDir = config.home.homeDirectory;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.proton-pass = {
    enable = lib.mkEnableOption "Proton Pass password manager";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Auto-start Proton Pass on login";
    };

    browserIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable browser extension integration";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = (session.packages or []);
    home.sessionVariables = (session.env or {});
    systemd.user.services = (session.services or {});
    home.file = lib.mkMerge [
      (appearance.files homeDir)
      (behavior.files homeDir)
    ];
  };
}