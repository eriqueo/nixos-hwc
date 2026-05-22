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
#   4. Create DNS CNAMEs: {service}.heartwoodcraft.me → <TUNNEL_ID>.cfargotunnel.com
#      Active: n8n, mcp, jobber, leads
#   5. Set tunnelId below and rebuild

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.networking.cloudflared;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.networking.cloudflared = {
    enable = lib.mkEnableOption "Cloudflare Tunnel for public webhook ingress";

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
      type = lib.types.str;
      default = "n8n.heartwoodcraft.me";
      description = "Primary public hostname (default: n8n ingress)";
    };

    n8nPort = lib.mkOption {
      type = lib.types.port;
      default = config.hwc.automation.n8n.port or 5678;
      defaultText = "config.hwc.automation.n8n.port";
      description = "Local n8n port to proxy to";
    };

    extraIngress = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Additional hostname → service ingress rules";
      example = { "status.heartwoodcraft.me" = "http://localhost:3000"; };
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
          default = "http_status:404";

          ingress = {
            ${cfg.domain} = "http://localhost:${toString cfg.n8nPort}";
          } // cfg.extraIngress;
        };
      };

      assertions = [
        {
          assertion = cfg.tunnelId != "";
          message = "hwc.networking.cloudflared.tunnelId must be set (run: cloudflared tunnel create hwc-server)";
        }
      ];
    })
  ];
}
