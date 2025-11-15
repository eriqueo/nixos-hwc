{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.ai.mcp = {
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
          default = [
            "/home/eric/.nixos"
            "/home/eric/.nixos-mcp-drafts"
          ];
          description = "Directories accessible to the filesystem MCP server";
        };

        draftsDir = mkOption {
          type = types.path;
          default = "/home/eric/.nixos-mcp-drafts";
          description = "Directory for LLM-proposed changes (read/write)";
        };

        user = mkOption {
          type = types.str;
          default = "eric";
          description = "User to run the filesystem MCP server as";
        };
      };
    };

    # Reverse proxy configuration
    reverseProxy = {
      enable = mkEnableOption "Expose MCP servers via Caddy reverse proxy" // { default = true; };

      path = mkOption {
        type = types.str;
        default = "/mcp";
        description = "URL path for MCP proxy endpoint";
      };
    };
  };
}
