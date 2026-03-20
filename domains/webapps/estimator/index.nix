# domains/webapps/estimator/index.nix
#
# Heartwood Estimate Assembler — Static React PWA
# NAMESPACE: hwc.webapps.estimator.*
#
# Moved from domains/business/estimator/ — the estimator is a web app,
# not a business service, so it lives here under the webapps domain.
#
# Serves the pre-built Vite dist/ via Caddy on a dedicated Tailscale port.
# Build steps (run on the server after updating files):
#
#   cd ~/.nixos/workspace/projects/react/heartwood-assembler
#   npm install && npm run build    # → dist/
#   sudo systemctl reload caddy
#
# Access: https://hwc.ocelot-wahoo.ts.net:13443
#
{ config, lib, ... }:
let
  cfg  = config.hwc.webapps.estimator;
  root = config.hwc.networking.shared.rootHost or "localhost";
in {
  # ── OPTIONS ───────────────────────────────────────────────────────────────
  options.hwc.webapps.estimator = {
    enable = lib.mkEnableOption "Heartwood Estimate Assembler PWA";

    distDir = lib.mkOption {
      type        = lib.types.path;
      description = "Path to the Vite build output (dist/) directory on the server.";
      example     = "/home/eric/.nixos/workspace/projects/react/heartwood-assembler/dist";
    };

    port = lib.mkOption {
      type        = lib.types.port;
      default     = 13443;
      description = "Tailscale HTTPS port for the estimator. 13443 is pre-allocated.";
    };

    webhookUrl = lib.mkOption {
      type        = lib.types.str;
      default     = "";
      description = "Optional n8n webhook URL (used at build time as VITE_WEBHOOK_URL).";
    };
  };

  # ── IMPLEMENTATION ────────────────────────────────────────────────────────
  config = lib.mkIf cfg.enable {
    # Caddy virtual host: static file server on dedicated Tailscale port
    services.caddy.extraConfig = lib.mkAfter ''

      # Heartwood Estimate Assembler — React PWA
      ${root}:${toString cfg.port} {
        tls {
          get_certificate tailscale
          protocols tls1.2 tls1.3
        }
        encode zstd gzip

        root * ${cfg.distDir}
        file_server

        # SPA fallback — unknown paths serve index.html
        try_files {path} /index.html

        # PWA cache headers
        @immutable path /assets/*
        header @immutable Cache-Control "public, max-age=31536000, immutable"

        @sw path /sw.js
        header @sw Cache-Control "no-cache"

        header / Cache-Control "no-cache"
      }
    '';

    # Open the estimator port on the Tailscale interface
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];
  };
}
