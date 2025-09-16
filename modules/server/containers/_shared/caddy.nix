{ lib, config, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkOption types mkIf concatStringsSep;
  routes = config.hwc.services.shared.routes;
  renderRoute = r:
    let
      path = r.path or "/";
      upstream = r.upstream;
      strip   = r.stripPrefix or false;
    in
      if strip then ''
        handle_path ${path}/* {
          reverse_proxy ${upstream}
        }
      '' else ''
        handle ${path} { redir ${path}/ 301 }
        route ${path}* {
          reverse_proxy ${upstream} {
            header_up Host {host}
            header_up X-Forwarded-Host {host}
            header_up X-Forwarded-Proto {scheme}
            header_up X-Forwarded-Port {server_port}
            header_up X-Forwarded-For {remote}
            header_up X-Real-IP {remote}
          }
        }
      '';
in
{
  options.hwc.services.reverseProxy = {
    enable = mkEnableOption "Aggregate service routes into a single Caddy vhost";
    domain = mkOption { type = types.str; default = "localhost"; };
  };

  config = mkIf config.hwc.services.reverseProxy.enable {
    services.caddy = {
      enable = true;
      virtualHosts."${config.hwc.services.reverseProxy.domain}".extraConfig =
        concatStringsSep "\n" (map renderRoute routes);
    };
    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
