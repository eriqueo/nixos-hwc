# domains/system/mcp/parts/caddy.nix
#
# Caddy configuration for MCP servers:
#   1. Port 6243 — tailnet-only TLS route to hwc-infra MCP
#   2. Port 18080 — MCP gateway (Funnel :443 → Caddy → backends)
#      Routes: default → hwc-infra MCP (:6200)
#              /n8n/*  → n8n-mcp bridge (:6201)

{ config, options, lib, ... }:

let
  cfg = config.hwc.system.mcp;
  hasNetworking = (options.hwc ? networking) && (options.hwc.networking ? shared);
  mcpEnabled = cfg.enable && (cfg.transport == "sse" || cfg.transport == "both");

  rootHost = if hasNetworking
    then config.hwc.networking.shared.rootHost
    else "hwc.ocelot-wahoo.ts.net";

  n8nBridge = config.hwc.automation.n8n.mcpBridge;

  # Internal auth token for n8n-mcp bridge (Caddy injects this header)
  n8nBridgeAuthToken = "hwc-n8n-mcp-internal-bridge-token-do-not-expose-externally";
in
{
  config = lib.mkMerge [
    # Tailnet-only TLS route — only when networking module exists
    # optionalAttrs prevents the option definition from being proposed on machines
    # that don't have the hwc.networking module (e.g., gaming)
    (lib.optionalAttrs hasNetworking (lib.mkIf mcpEnabled {
      hwc.networking.shared.routes = [
        {
          name = "infra-mcp";
          mode = "port";
          port = 6243;
          upstream = "http://127.0.0.1:${toString cfg.port}";
        }
      ];
    }))

    # MCP gateway on :18080 — Funnel :443 terminates TLS and proxies here
    (lib.mkIf mcpEnabled {
      services.caddy.extraConfig = lib.mkAfter ''
        :18080 {
          ${lib.optionalString n8nBridge.enable ''
          # n8n MCP bridge: /n8n/* → strip prefix → localhost:${toString n8nBridge.port}
          handle_path /n8n/* {
            reverse_proxy http://127.0.0.1:${toString n8nBridge.port} {
              header_up Authorization "Bearer ${n8nBridgeAuthToken}"
              header_up X-Forwarded-Proto https
              header_up X-Forwarded-Host ${rootHost}
              flush_interval -1
            }
          }
          ''}

          # Default: hwc-infra MCP server
          handle {
            reverse_proxy http://127.0.0.1:${toString cfg.port} {
              header_up X-Forwarded-Proto https
              header_up X-Forwarded-Host ${rootHost}
              flush_interval -1
            }
          }
        }
      '';
    })
  ];
}
