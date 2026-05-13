# domains/server/native/ai/jobber-mcp/options.nix
#
# Jobber MCP Server options — exposes Jobber GraphQL API as MCP tools via SSE
{ lib, config, ... }:
let
  paths = config.hwc.paths;
in
{
  options.hwc.server.ai.jobberMcp = {
    enable = lib.mkEnableOption "Jobber MCP Server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8002;
      description = "Internal port the Jobber MCP server listens on";
    };

    reverseProxyPort = lib.mkOption {
      type = lib.types.port;
      default = 20443;
      description = "External Tailscale HTTPS port for Caddy reverse proxy";
    };

    projectDir = lib.mkOption {
      type = lib.types.path;
      default = "/home/eric/projects/jobber-mcp";
      description = "Path to the jobber-mcp Python project";
    };

    envFile = lib.mkOption {
      type = lib.types.path;
      default = "/home/eric/projects/jobber-mcp/.env";
      description = "Path to .env file containing JOBBER_ACCESS_TOKEN and OAuth credentials";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "User to run the service as";
    };
  };
}
