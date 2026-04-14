{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.networking.gluetun;
  inherit (lib) mkOption mkEnableOption types;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.networking.gluetun = {
    enable = mkEnableOption "gluetun container";
    image  = mkOption { type = types.str; default = "qmcgaw/gluetun:latest"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };

    portForwarding = {
      enable = mkEnableOption "VPN port forwarding via NAT-PMP";

      syncToQbittorrent = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically sync forwarded port to qBittorrent";
      };

      checkInterval = mkOption {
        type = types.int;
        default = 60;
        description = "Seconds between port sync checks";
      };
    };

    healthCheck = {
      enable = mkEnableOption "VPN + port forwarding health monitor with Gotify alerts";

      checkInterval = mkOption {
        type = types.int;
        default = 300;
        description = "Seconds between health checks";
      };

      failuresBeforeRestart = mkOption {
        type = types.int;
        default = 3;
        description = "Consecutive failures before auto-restarting gluetun";
      };

      failuresBeforeAlert = mkOption {
        type = types.int;
        default = 2;
        description = "Consecutive failures before sending a Gotify alert";
      };
    };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
    ./parts/scripts.nix
    ./parts/pkgs.nix
    ./parts/lib.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # VPN secrets are declared in domains/secrets/declarations/infrastructure.nix
    # Accessible via config.age.secrets.vpn-username.path and config.age.secrets.vpn-password.path

    # Validation assertions
    assertions = [
      {
        assertion = config.hwc.secrets.enable;
        message = "Gluetun requires hwc.secrets.enable = true for VPN credentials";
      }
      {
        assertion = config.virtualisation.oci-containers.backend == "podman";
        message = "Gluetun requires Podman as OCI container backend";
      }
    ];
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Validation logic above within config block
}
