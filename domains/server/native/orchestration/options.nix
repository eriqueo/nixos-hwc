# domains/server/orchestration/options.nix
# Feature toggle for orchestration helpers (media orchestrator, etc.)

{ lib, ... }:
{
  options.hwc.server.orchestration = {
    enable = lib.mkEnableOption "orchestration helpers" // { default = true; };
  };
}
