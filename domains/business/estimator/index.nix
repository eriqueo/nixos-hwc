# domains/business/estimator/index.nix
#
# Heartwood Estimate Assembler — Static React PWA
# NAMESPACE: hwc.business.estimator.*
#
# Serves the pre-built Vite dist/ via Caddy on a dedicated Tailscale port.
# Build steps (run on the server after updating files):
#
#   cd ~/.nixos/workspace/business/estimator-pwa
#   npm install
#   npm run build          # → dist/
#   sudo systemctl reload caddy
#
# Access: https://hwc.ocelot-wahoo.ts.net:13443
#
{ config, lib, ... }:
let
  cfg  = config.hwc.business.estimator;
  root = config.hwc.networking.shared.rootHost;
in {
  # ── OPTIONS ───────────────────────────────────────────────────────────────
  options.hwc.business.estimator = {
    enable = lib.mkEnableOption "Heartwood Estimate Assembler PWA";

    distDir = lib.mkOption {
      type        = lib.types.path;
      description = "Path to the Vite build output (dist/) directory on the server.";
      example     = "/home/eric/.nixos/workspace/business/estimator-pwa/dist";
    };

    port = lib.mkOption {
      type        = lib.types.port;
      default     = 13443;
      description = "Tailscale HTTPS port to expose the app on. Must be 443, 8443, or 10000 for Funnel.";
    };

    webhookUrl = lib.mkOption {
      type        = lib.types.str;
      default     = "";
      description = "Optional n8n webhook URL injected as VITE_WEBHOOK_URL at build time.";
    };
  };

  # ── IMPLEMENTATION ────────────────────────────────────────────────────────
  config = lib.mkIf cfg.enable {
    # Caddy virtual host: serve static files on the dedicated port
    services.caddy.extraConfig = lib.mkAfter ''

      # Heartwood Estimate Assembler — PWA
      ${root}:${toString cfg.port} {
        tls {
          get_certificate tailscale
          protocols tls1.2 tls1.3
        }
        encode zstd gzip

        root * ${cfg.distDir}
        file_server

        # SPA fallback — all unknown paths serve index.html
        try_files {path} /index.html

        # PWA / cache headers
        @immutable path /assets/*
        header @immutable Cache-Control "public, max-age=31536000, immutable"

        @sw path /sw.js
        header @sw Cache-Control "no-cache"

        header / Cache-Control "no-cache"
      }
    '';

    # Open the port in the firewall (Tailscale interface only)
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];
  };
}
