{ lib, config, ... }:
let
  cfg = config.hwc.server.native.orchestration;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./media-orchestrator.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Enable media orchestrator by default for server
    hwc.server.native.orchestration.mediaOrchestrator.enable = lib.mkDefault true;  # Fixed: now uses agenix
    assertions = [];
  };

}
