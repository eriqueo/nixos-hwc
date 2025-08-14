{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.caddy;
in {
  options.hwc.services.caddy = {
    enable = lib.mkEnableOption "Caddy reverse proxy";
    
    email = lib.mkOption {
      type = lib.types.str;
      default = "admin@example.com";
      description = "Email for ACME";
    };
    
    sites = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = {};
      description = "Site configurations";
      example = {
        "jellyfin.local" = ''
          reverse_proxy localhost:8096
        '';
      };
    };
  };
  
  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
      email = cfg.email;
      
      virtualHosts = lib.mapAttrs (name: config: {
        extraConfig = config;
      }) cfg.sites;
    };
    
    services.caddy.virtualHosts = lib.mkMerge [
      (lib.mkIf config.hwc.services.jellyfin.enable {
        "jellyfin.local".extraConfig = ''
          reverse_proxy localhost:${toString config.hwc.services.jellyfin.port}
        '';
      })
      
      (lib.mkIf config.hwc.services.grafana.enable {
        "grafana.local".extraConfig = ''
          reverse_proxy localhost:${toString config.hwc.services.grafana.port}
        '';
      })
    ];
    
    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
