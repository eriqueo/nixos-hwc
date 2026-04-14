# domains/home/apps/proton-authenticator/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.proton-authenticator;
  session = import ./parts/session.nix { inherit lib pkgs config; };
  toggleScript = import ./parts/toggle-script.nix { inherit pkgs; };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.proton-authenticator = {
    enable = lib.mkEnableOption "Proton Authenticator";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Auto-start Proton Authenticator on login";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = (session.packages or []) ++ [ toggleScript ];
    home.sessionVariables = (session.env or {});
    systemd.user.services = (session.services or {});
    xdg.configFile = (session.autostartFiles or {});
  };
}
