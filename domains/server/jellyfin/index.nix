{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.jellyfin;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Native Jellyfin service configuration
    services.jellyfin = {
      enable = true;
      openFirewall = cfg.openFirewall;
    };

    # Register reverse proxy route if enabled
    hwc.services.shared.routes = lib.mkIf cfg.reverseProxy.enable [
      {
        path = cfg.reverseProxy.path;
        upstream = cfg.reverseProxy.upstream;
        stripPrefix = true;
      }
    ];

    # Manual firewall configuration (matching /etc/nixos pattern)
    networking.firewall = lib.mkIf (!cfg.openFirewall) {
      allowedTCPPorts = [ 8096 7359 ];  # HTTP + TCP discovery
      allowedUDPPorts = [ 7359 ];       # UDP discovery
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.reverseProxy.enable || config.hwc.services.reverseProxy.enable;
        message = "hwc.server.jellyfin.reverseProxy requires hwc.services.reverseProxy.enable = true";
      }
    ];
  };
}