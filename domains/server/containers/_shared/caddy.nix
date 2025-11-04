{ lib, config, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkOption types mkIf concatStringsSep;

  tailscaleDomain = config.hwc.services.shared.tailscaleDomain;
  rootHost        = config.hwc.services.shared.rootHost;
  routes          = config.hwc.services.shared.routes;

  # Render a route -> Caddy snippet
  renderRoute = r:
    let
      # schema defaults
      assetGlobs    = r.assetGlobs or [ "/css/*" "/js/*" "/assets/*" "/images/*" "/static/*" "/fonts/*" "/webfonts/*" "/favicon.ico" ];
      assetStrategy = r.assetStrategy or "none";
      headers       = r.headers or {};
      needsUrlBase  = r.needsUrlBase or false;      # NEW: drives preserve vs strip
      stripPrefix   = r.stripPrefix or false;       # deprecated; ignored when needsUrlBase = true
      ws            = r.ws or true;                 # enable websocket support by default
      timeouts      = r.timeouts or { try = "10s"; fail = "5s"; };

      # header_up block from r.headers
      renderHeaders = concatStringsSep "\n" (lib.mapAttrsToList (name: value: "header_up ${name} ${value}") headers);

      # common reverse_proxy block (no invalid transport stanza)
      proxyBlock = ''
        reverse_proxy ${r.upstream} {
          header_up X-Real-IP {remote}
          ${renderHeaders}
          ${lib.optionalString ws "flush_interval -1"}
        }
      '';

      # legacy/optional asset handlers (default is none)
      assetHandlers = {
        none = "";
        rewrite = ''
          @assets_${r.name} path ${concatStringsSep " " assetGlobs}
          rewrite @assets_${r.name} ${r.path}{uri}
        '';
        referer = ''
          @assets_${r.name} {
            path ${concatStringsSep " " assetGlobs}
            header Referer *${r.path}*
          }
          handle @assets_${r.name} {
            ${proxyBlock}
          }
        '';
      };

      # helpers to emit preserve/strip variants for subpaths
      subpathPreserve = ''
        @${r.name} path ${r.path}*
        redir ${r.path} ${r.path}/ 301
        handle @${r.name} {
          ${proxyBlock}
        }
        ${assetHandlers.${assetStrategy}}
      '';

      subpathStrip = ''
        redir ${r.path} ${r.path}/ 301
        handle_path ${r.path}* {
          ${proxyBlock}
        }
        ${assetHandlers.${assetStrategy}}
      '';
    in
      if r.mode == "subpath" then
        # If the app has a URL base, we must preserve the path; otherwise we may strip.
        (if needsUrlBase then subpathPreserve else subpathStrip)
      else if r.mode == "port" then ''
        # Dedicated TLS listener on the tailscale host:port
        ${rootHost}:${toString r.port} {
          tls { get_certificate tailscale }
          encode zstd gzip
          ${proxyBlock}
        }
      ''
      else "";

in
{
  options.hwc.services.reverseProxy = {
    enable = mkEnableOption "Reverse proxy service (Caddy)";
    domain = mkOption {
      type = types.str;
      default = "hwc.ocelot-wahoo.ts.net";
      description = "Domain for reverse proxy services";
    };
  };

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
      # New schema keys supported per route:
      # name, mode=("subpath"|"port"), path, port, upstream,
      # needsUrlBase=bool, stripPrefix=bool (deprecated),
      # headers=attrs, assetGlobs, assetStrategy, ws=bool, timeouts={try,fail}
      type = types.listOf (types.attrsOf types.anything);
      default = [];
      description = "Aggregated reverse proxy routes for all services.";
    };
  };

  config = mkIf config.hwc.services.reverseProxy.enable {
    services.caddy = {
      enable = true;
      extraConfig = ''
        ${rootHost} {
          tls { get_certificate tailscale }
          encode zstd gzip
          ${concatStringsSep "\n" (map renderRoute (lib.filter (r: r.mode == "subpath") routes))}
        }

        ${concatStringsSep "\n" (map renderRoute (lib.filter (r: r.mode == "port") routes))}
      '';
    };

    networking.firewall.allowedTCPPorts =
      [ 80 443 ]
      ++ (lib.map (r: r.port) (lib.filter (r: r.mode == "port") routes));
  };
}
