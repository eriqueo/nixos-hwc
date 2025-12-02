# domains/ai/legacy-compat.nix
{ config, lib, ... }:
let
  serverAi = config.hwc.server.ai or {};
in
{
  # If old options exist, map them so the new domains read values.
  # This is temporary during migration.
  config = lib.mkIf (serverAi != {}) {
    hwc.ai = {
      ollama = serverAi.ollama or {};
      open-webui = serverAi.open-webui or {};
      local-workflows = serverAi.local-workflows or {};
      mcp = serverAi.mcp or {};
    };
  };
}
