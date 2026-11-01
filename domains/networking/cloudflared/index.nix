# domains/networking/cloudflared/index.nix
#
# Cloudflare Tunnel — publicly resolvable ingress for external-facing services.
# Wraps the built-in NixOS services.cloudflared module.
#
# NAMESPACE: hwc.networking.cloudflared.*
#
# DEPENDENCIES:
#   - agenix secret: cloudflared-tunnel-credentials (JSON credentials file)
#
# SETUP (one-time, interactive):
#   1. cloudflared tunnel login            → ~/.cloudflared/cert.pem
#   2. cloudflared tunnel create hwc-server → ~/.cloudflared/<TUNNEL_ID>.json
#   3. Encrypt credentials JSON with agenix
#   4. Create DNS CNAMEs in Cloudflare for each ingress hostname:
#        {service}.iheartwoodcraft.com → <TUNNEL_ID>.cfargotunnel.com
#      Create Access restrictions before publishing protected origins.
#   5. Set tunnelId below and rebuild
# See wiki/nixos/iheartwoodcraft-com-backend-migration.md for the
# operator runbook covering the api.iheartwoodcraft.com migration.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.networking.cloudflared;
  origins = lib.mapAttrs (_: value:
    if builtins.isString value then { service = value; } else value
  ) (lib.optionalAttrs (cfg.domain != null) {
    ${cfg.domain} = "http://${cfg.n8nHost}:${toString cfg.n8nPort}";
  } // cfg.extraIngress);
  loggerOrigin = "http://127.0.0.1:${toString cfg.accessLog.port}";
  # One producer for public destinations and path gates. The fallback crosses
  # this listener too, so repeat the original selectors before proxying.
  originRoutes = lib.concatStringsSep "\n" (lib.imap0 (i: hostname:
    let rule = origins.${hostname}; name = "origin${toString i}";
    in ''
      @${name} {
        host ${hostname}
        ${lib.optionalString (rule ? path) "path_regexp ${name} ${rule.path}"}
      }
      handle @${name} {
        reverse_proxy ${rule.service} {
          trusted_proxies 127.0.0.1/32 ::1/128
          # Preserve the tunnel's existing proxy-hop contract (n8n trusts one
          # hop); appending this loopback hop would hide the actual client.
          header_up X-Forwarded-For {http.request.header.X-Forwarded-For}
          flush_interval -1
        }
      }
    ''
  ) (lib.attrNames origins));
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.networking.cloudflared = {
    enable = lib.mkEnableOption "Cloudflare Tunnel for public webhook ingress";

    accessLog = {
      enable = lib.mkEnableOption "bounded, sanitized logs for every origin tunnel request";
      port = lib.mkOption {
        type = lib.types.port;
        default = 8097;
        description = "Loopback-only Caddy origin logging proxy port; never open in the firewall";
      };
    };

    tunnelId = lib.mkOption {
      type = lib.types.str;
      description = "Cloudflare Tunnel UUID (from `cloudflared tunnel create`)";
      example = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to tunnel credentials JSON file (via agenix)";
    };

    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Optional whole-host n8n ingress. Leave null for path-restricted webhook
        ingress through extraIngress. Legacy hostnames must be explicit at the
        machine rather than silently surviving as a module default.
      '';
    };

    n8nPort = lib.mkOption {
      type = lib.types.port;
      default = config.hwc.automation.n8n.port or 5678;
      defaultText = "config.hwc.automation.n8n.port";
      description = "Local n8n port to proxy to";
    };

    n8nHost = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = ''
        Host that serves n8n for the primary `domain`. `localhost` when the
        tunnel and n8n share a host; a tailnet address when they do not
        (service split: the tunnel runs on hwc-work, n8n on hwc-server
        until wave 4).
      '';
    };

    extraIngress = lib.mkOption {
      type = lib.types.attrsOf (lib.types.either lib.types.str lib.types.attrs);
      default = {};
      description = ''
        Additional hostname → service ingress rules. A plain string routes
        the whole hostname; an attrset ({ service; path; originRequest; })
        routes only request paths matching the regex — unmatched paths fall
        through to the tunnel default (404) — and may set per-rule origin
        options such as httpHostHeader/originServerName for an HTTPS origin
        reached by IP. The attrset passes through to the nixpkgs
        services.cloudflared ingress submodule, which validates it.
      '';
      example = {
        "status.iheartwoodcraft.com" = "http://localhost:3000";
        "api.iheartwoodcraft.com" = { service = "http://localhost:5678"; path = "^/webhook/"; };
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkMerge [
    # CLI always available for tunnel setup (login, create, route dns)
    { environment.systemPackages = [ pkgs.cloudflared ]; }

    # Tunnel service — only when fully configured
    (lib.mkIf cfg.enable {
      services.cloudflared = {
        enable = true;

        tunnels.${cfg.tunnelId} = {
          credentialsFile = cfg.credentialsFile;
          default = if cfg.accessLog.enable then loggerOrigin else "http_status:404";

          ingress = lib.mapAttrs (_: rule:
            if cfg.accessLog.enable then rule // { service = loggerOrigin; }
            else rule
          ) origins;
        };
      };

      assertions = [
        {
          assertion = cfg.tunnelId != "";
          message = "hwc.networking.cloudflared.tunnelId must be set (run: cloudflared tunnel create hwc-server)";
        }
      ];
    })

    (lib.mkIf (cfg.enable && cfg.accessLog.enable) {
      assertions = [ {
        assertion = config.services.caddy.enable && lib.all (rule:
          lib.hasPrefix "http://" rule.service && !(rule ? originRequest)
          && rule.service != loggerOrigin
        ) (lib.attrValues origins);
        message = "Tunnel access logging requires Caddy and non-recursive HTTP origins without originRequest overrides";
      } ];
      services.caddy.virtualHosts."http://:${toString cfg.accessLog.port}" = {
        # AUTO-MANAGED security metadata: drop oldest at either retention bound.
        logFormat = ''
          output file /var/log/caddy/access-public-origin.log {
            mode 0600
            roll_size 50MiB
            roll_at 00:00
            roll_keep 30
            roll_keep_for 30d
          }
          format filter {
            wrap json
            fields {
              request>headers delete
              request>uri delete
              resp_headers delete
              path regexp "^/(api/reports|report)/.*" "/report/[redacted]"
            }
          }
        '';
        extraConfig = ''
          bind 127.0.0.1
          log_append schemaVersion 1
          log_append <path {path}
          log_append request_id {http.request.header.Cf-Ray}
          log_append client_ip {http.request.header.Cf-Connecting-Ip}
          ${originRoutes}
          handle {
            respond 404
          }
        '';
      };
      systemd.services."cloudflared-tunnel-${cfg.tunnelId}" = {
        requires = [ "caddy.service" ];
        after = [ "caddy.service" ];
      };
    })
  ];
}
