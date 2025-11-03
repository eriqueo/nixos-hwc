{ lib, config, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkOption types mkIf concatStringsSep;

  # Global settings from the new schema
  tailscaleDomain = config.hwc.services.shared.tailscaleDomain;
  rootHost = config.hwc.services.shared.rootHost;
  routes = config.hwc.services.shared.routes;

  # Function to render a single route configuration
  renderRoute = r:
    let
      # Default values
      assetGlobs = r.assetGlobs or [ "/css/*" "/js/*" "/assets/*" "/images/*" "/static/*" ];
      assetStrategy = r.assetStrategy or "none";
      headers = r.headers or {};
      stripPrefix = r.stripPrefix or false;

      # Helper to generate header_up block
      renderHeaders = concatStringsSep "\n" (lib.mapAttrsToList (name: value: "header_up ${name} ${value}") headers);

      # Base reverse_proxy block with WebSocket support
      proxyBlock = ''
        reverse_proxy ${r.upstream} {
          transport http {
            versions h1c h2c
          }
          ${renderHeaders}
        }
      '';

      # Asset handling strategies
      assetHandlers = {
        none = "";
        rewrite = ''
          @assets_${r.name} path ${concatStringsSep " " assetGlobs}
          handle @assets_${r.name} {
            ${proxyBlock}
          }
        '';
        referer = ''
          @assets_with_referer_${r.name} {
            path ${concatStringsSep " " assetGlobs}
            header Referer *${r.path}*
          }
          handle @assets_with_referer_${r.name} {
            ${proxyBlock}
          }
        '';
      };

    in
    # Main logic to generate Caddyfile based on mode
    if r.mode == "subpath" then ''
      # Route for ${r.name} at ${rootHost}${r.path}
      handle_path ${r.path}* {
        ${proxyBlock}
      }
      ${assetHandlers.${assetStrategy}}
    ''
    else if r.mode == "port" then ''
      # Listener for ${r.name} at ${rootHost}:${toString r.port}
      ${rootHost}:${toString r.port} {
        tls {
          get_certificate tailscale
        }
        encode zstd gzip
        ${proxyBlock}
      }
    ''
    else ""; # Should not happen with proper schema

in
{
  # New centralized schema for reverse proxy settings
  options.hwc.services.shared = {
    tailscaleDomain = mkOption {
      type = types.str;
      default = "hwc.ocelot-wahoo.ts.net";
      description = "Tailscale domain for the server.";
    };
    rootHost = mkOption {
      type = types.str;
      default = "hwc.ocelot-wahoo.ts.net";
      description = "Root host for subpath and port-based services.";
    };
    routes = mkOption {
      type = types.listOf (types.attrsOf types.anything);
      default = [];
      description = "Aggregated reverse proxy routes for all services.";
    };
  };

  # Main Caddy configuration
  config = mkIf config.hwc.services.reverseProxy.enable {
    services.caddy = {
      enable = true;
      # Global settings for the root host
      virtualHosts."${rootHost}" = {
        extraConfig = ''
          encode zstd gzip
          ${concatStringsSep "\n" (map renderRoute (lib.filter (r: r.mode == "subpath") routes))}
        '';
        tls {
          get_certificate tailscale;
        }
      };

      # Additional virtual hosts for ports
      extraConfig = concatStringsSep "\n" (map renderRoute (lib.filter (r: r.mode == "port") routes));
    };

    # Firewall settings
    networking.firewall.allowedTCPPorts = [ 80 443 ] ++ (lib.map (r: r.port) (lib.filter (r: r.mode == "port") routes));
  };
}
