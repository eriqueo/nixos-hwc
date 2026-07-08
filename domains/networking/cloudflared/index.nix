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
#        {service}.heartwoodcraft.me → <TUNNEL_ID>.cfargotunnel.com   (active)
#        {service}.api.iheartwoodcraft.com → <TUNNEL_ID>.cfargotunnel.com
#        (Phase 4.6 in progress; needs api.iheartwoodcraft.com
#         delegated from Hostinger to Cloudflare first — NS record at
#         the apex zone pointing `api` to the Cloudflare nameservers.)
#   5. Set tunnelId below and rebuild
# See wiki/nixos/iheartwoodcraft-com-backend-migration.md for the
# operator runbook covering the api.iheartwoodcraft.com migration.

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
      type = lib.types.attrsOf (lib.types.either lib.types.str (lib.types.attrsOf lib.types.str));
      default = {};
      description = ''
        Additional hostname → service ingress rules. A plain string routes
        the whole hostname; an attrset ({ service; path; }) routes only
        request paths matching the regex — unmatched paths fall through to
        the tunnel default (404). Path form passes through to the nixpkgs
        services.cloudflared ingress submodule.
      '';
      example = {
        "status.heartwoodcraft.me" = "http://localhost:3000";
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
