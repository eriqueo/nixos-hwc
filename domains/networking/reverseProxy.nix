{ lib, config, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkOption types mkIf concatStringsSep;

  tailscaleDomain = config.hwc.networking.shared.tailscaleDomain;
  rootHost        = config.hwc.networking.shared.rootHost;
  routes          = config.hwc.networking.shared.routes;

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
          header_up Host {host}
          header_up X-Real-IP {remote}
          header_up X-Forwarded-For {remote}
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-Host {host}
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
      # Static file server block (for mode = "static")
      staticBlock = ''
        # Static file server on dedicated TLS port
        ${rootHost}:${toString r.port} {
          tls {
            get_certificate tailscale
            protocols tls1.2 tls1.3
            alpn h2 http/1.1
          }
          encode zstd gzip

          # CORS headers for cross-origin embedding
          header Access-Control-Allow-Origin "*"
          header Access-Control-Allow-Methods "GET, OPTIONS"
          header Access-Control-Allow-Headers "Content-Type"

          # Cache static assets
          header Cache-Control "public, max-age=31536000, immutable"

          root * ${r.root}
          try_files {path} /index.html
          file_server
        }
      '';
    in
      if r.mode == "subpath" then
        # If the app has a URL base, we must preserve the path; otherwise we may strip.
        (if needsUrlBase then subpathPreserve else subpathStrip)
      else if r.mode == "port" then ''
        # Dedicated TLS listener on the tailscale host:port
        ${rootHost}:${toString r.port} {
          tls {
            get_certificate tailscale
            protocols tls1.2 tls1.3
            alpn h2 http/1.1
          }
          encode zstd gzip
          ${proxyBlock}
        }
      ''
      else if r.mode == "static" then staticBlock
      else "";

in
{
  options.hwc.networking.reverseProxy = {
    enable = mkEnableOption "Reverse proxy service (Caddy)";
    domain = mkOption {
      type = types.str;
      default = "hwc.ocelot-wahoo.ts.net";
      description = "Domain for reverse proxy services";
    };
  };

  options.hwc.networking.shared = {
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

  config = mkIf config.hwc.networking.reverseProxy.enable {
    services.caddy = {
      enable = true;
      extraConfig = ''
        # Loopback-only access to subpath routes.
        # Explicit bind prevents Caddy's default *:443 wildcard, which would
        # race with tailscaled for the Tailscale IP on :443.
        localhost {
          bind 127.0.0.1
          tls internal
          encode zstd gzip
          ${concatStringsSep "\n" (map renderRoute (lib.filter (r: r.mode == "subpath") routes))}
        }

        # Tailscale serve backend — plain HTTP, no TLS.
        # tailscaled terminates TLS for both tailnet and Funnel traffic on :443,
        # then proxies here. Handles MCP routes + all subpath routes so that
        # tailnet clients keep accessing hwc.ocelot-wahoo.ts.net/sonarr etc.
        :18080 {
          encode zstd gzip

          # MCP routes — proxy to hwc-infra Express server (priority over subpath routes)
          @mcp_routes {
            path /mcp /mcp/* /health /.well-known/*
          }
          handle @mcp_routes {
            reverse_proxy 127.0.0.1:6200 {
              flush_interval -1
              transport http {
                read_timeout 0
                write_timeout 0
              }
            }
          }

          # All subpath routes (sonarr, radarr, navidrome, etc.)
          ${concatStringsSep "\n" (map renderRoute (lib.filter (r: r.mode == "subpath") routes))}
        }

        ${concatStringsSep "\n" (map renderRoute (lib.filter (r: r.mode == "port") routes))}

        ${concatStringsSep "\n" (map renderRoute (lib.filter (r: r.mode == "static") routes))}

        # Public MCP gateway — Tailscale Funnel on :10000 terminates TLS,
        # forwards to this HTTP-only listener. Only MCP, OAuth, and webhook
        # paths are allowed; everything else gets 403.
        :10080 {
          @mcp_allowed {
            path /mcp /mcp/* /mcp-server /mcp-server/* /mcp-oauth /mcp-oauth/* /.well-known/* /rest/oauth2-credential/* /webhook/* /webhook-test/*
          }

          handle @mcp_allowed {
            reverse_proxy 127.0.0.1:5678 {
              header_up X-Forwarded-Proto https
              header_up X-Forwarded-Host ${rootHost}:10000
              flush_interval -1
            }
          }

          handle {
            respond 403
          }
        }
      '';
    };

    # Run caddy as eric user for simplified permissions
    systemd.services.caddy = {
      serviceConfig = {
        User = lib.mkForce "root";
        Group = lib.mkForce "root";
        # Disable security restrictions so eric can access directories
        PrivateUsers = lib.mkForce false;
        ProtectHome = lib.mkForce false;
      };
    };

    networking.firewall.allowedTCPPorts =
      [ 80 443 ]
      ++ (lib.map (r: r.port) (lib.filter (r: r.mode == "port" || r.mode == "static") routes));
  };
}
