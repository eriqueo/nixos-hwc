{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.ai.mcp = {
    enable = mkEnableOption "MCP (Model Context Protocol) server infrastructure";

    # Proxy configuration
    proxy = {
      enable = mkEnableOption "MCP proxy for stdio ↔ HTTP bridging" // { default = true; };

      port = mkOption {
        type = types.port;
        default = 6001;
        description = "Port for mcp-proxy HTTP listener (localhost only)";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Host address for mcp-proxy (should remain localhost)";
      };
    };

    # Filesystem MCP server
    filesystem = {
      nixos = {
        enable = mkEnableOption "Filesystem MCP server for ~/.nixos directory";

        allowedDirs = mkOption {
          type = types.listOf types.str;
          # Note: This will be dynamically set in default.nix based on actual user
          default = [];
          description = "Directories accessible to the filesystem MCP server";
        };

        draftsDir = mkOption {
          type = types.path;
          # Note: This will be dynamically set in default.nix based on actual user
          default = "/tmp/.nixos-mcp-drafts";
          description = "Directory for LLM-proposed changes (read/write)";
        };

        user = mkOption {
          type = types.str;
          # Note: This will be dynamically set in default.nix based on actual user config
          default = "";
          description = "User to run the filesystem MCP server as";
        };
      };
    };

    # Reverse proxy configuration
    reverseProxy = {
      enable = mkEnableOption "Expose MCP servers via Caddy reverse proxy" // { default = false; };

      path = mkOption {
        type = types.str;
        default = "/mcp";
        description = "URL path for MCP proxy endpoint";
      };

      authType = mkOption {
        type = types.enum [ "none" "basic" "apikey" ];
        default = "none";
        description = ''
          Authentication type for MCP reverse proxy:
          - none: No authentication (local network only)
          - basic: HTTP Basic authentication
          - apikey: API key in header (X-API-Key)
        '';
      };
    };
  };
}
