{ lib, config, ... }:
let
  cfg = config.hwc.server.orchestration;
in
{
  imports = [
    ./options.nix
    ./media-orchestrator.nix
  ];

  config = lib.mkIf cfg.enable {
    # Enable media orchestrator by default for server
    hwc.server.orchestration.mediaOrchestrator.enable = lib.mkDefault true;  # Fixed: now uses agenix
  };
}
