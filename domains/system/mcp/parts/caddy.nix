# domains/system/mcp/parts/caddy.nix
#
# Caddy TLS route for tailnet access to the unified MCP gateway.
# hwc.system.mcp.tailnetPort (6243) — tailnet-only TLS route; agent sessions on
# every host connect here through hwc.system.mcp.url.
#
# Note: Public Funnel access goes through :18080 → :6200.
# All tools (hwc-sys, JT, n8n) are served from the single /mcp endpoint.

{ config, options, lib, ... }:

let
  cfg = config.hwc.system.mcp;
  hasNetworking = (options.hwc ? networking) && (options.hwc.networking ? shared);
  mcpEnabled = cfg.enable && (cfg.transport == "sse" || cfg.transport == "both");
in
{
  # optionalAttrs guards the option path (no config reads = no recursion).
  # mkIf handles the config-dependent enable condition lazily.
  config = lib.optionalAttrs hasNetworking (lib.mkIf mcpEnabled {
    hwc.networking.shared.routes = [
      {
        name = "infra-mcp";
        mode = "port";
        port = cfg.tailnetPort;
        upstream = "http://127.0.0.1:${toString cfg.port}";
      }
    ];
  });
}
