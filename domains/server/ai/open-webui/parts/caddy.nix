# domains/server/ai/open-webui/parts/caddy.nix
#
# Caddy reverse proxy configuration for Open WebUI
# This creates a Caddyfile snippet that can be included in the main Caddy config

{ config, lib, pkgs, cfg }:

let
  # Generate Caddyfile snippet for Open WebUI
  caddyfileSnippet = lib.optionalString (cfg.domain != null) ''
    # Open WebUI - AI Assistant Interface
    ${cfg.domain} {
      # Reverse proxy to Open WebUI container
      reverse_proxy localhost:${toString cfg.port} {
        # WebSocket support for streaming responses
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
      }

      # Logging
      log {
        output file /var/log/caddy/open-webui.log
        format json
      }

      # Security headers
      header {
        # Enable HSTS
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        
        # Prevent clickjacking
        X-Frame-Options "SAMEORIGIN"
        
        # XSS Protection
        X-Content-Type-Options "nosniff"
        
        # Remove server header
        -Server
      }

      # Optional: Basic auth (if not using Open WebUI's built-in auth)
      # Uncomment and configure if needed
      # basicauth {
      #   eric $2a$14$...  # bcrypt hash
      # }
    }
  '';

  # Path where Caddyfile snippet will be written
  caddySnippetPath = "/etc/caddy/snippets/open-webui.caddy";
in
{
  # Create Caddyfile snippet
  environment.etc."caddy/snippets/open-webui.caddy" = lib.mkIf (cfg.domain != null) {
    text = caddyfileSnippet;
    mode = "0644";
  };

  # Create log directory
  systemd.tmpfiles.rules = lib.mkIf (cfg.domain != null) [
    "d /var/log/caddy 0750 caddy caddy -"
  ];

  # Note: The main Caddyfile needs to import this snippet
  # Add to your main Caddy configuration:
  # import /etc/caddy/snippets/*.caddy
}
