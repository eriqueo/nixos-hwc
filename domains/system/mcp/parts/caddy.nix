# domains/system/mcp/parts/caddy.nix
#
# Caddy reverse proxy route for SSE transport
# External port 6243 → internal 6200

{ config, lib, ... }:

let
  cfg = config.hwc.system.mcp;
  enabled = cfg.enable && (cfg.transport == "sse" || cfg.transport == "both");
in
{
  config = lib.mkIf enabled {
    hwc.networking.shared.routes = [
      {
        name = "infra-mcp";
        mode = "port";
        port = 6243;
        upstream = "http://127.0.0.1:${toString cfg.port}";
      }
    ];
  };
}
