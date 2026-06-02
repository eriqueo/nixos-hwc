# domains/server/native/ai/brain-mcp/options.nix
#
# Brain MCP Server options — exposes brain vault at /home/eric/900_vaults/brain as MCP tools
# Namespace: hwc.server.ai.brainMcp (matches folder: domains/server/native/ai/brain-mcp/)
{ lib, ... }:
{
  options.hwc.server.ai.brainMcp = {
    enable = lib.mkEnableOption "Brain MCP Server (Deno)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9876;
      description = "Internal port the Brain MCP server listens on (127.0.0.1 only)";
    };

    vaultPath = lib.mkOption {
      type = lib.types.path;
      default = "/home/eric/900_vaults/brain";
      description = "Path to the brain vault replica on the server";
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.path;
      default = "/run/agenix/brain-mcp-api-key";
      description = "Path to file containing the MCP Bearer token (agenix-decrypted)";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "User to run the Brain MCP service as";
    };

    reverseProxyPort = lib.mkOption {
      type = lib.types.port;
      default = 23443;
      description = "External Caddy HTTPS port for brain-mcp access via Tailscale (Phase 12)";
    };
  };
}
