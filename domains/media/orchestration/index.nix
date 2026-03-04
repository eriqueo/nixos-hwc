{ lib, config, ... }:
let
  cfg = config.hwc.media.orchestration;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./media-orchestrator.nix
    ./audiobook-copier/index.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Enable media orchestrator by default for server
    hwc.media.orchestration.mediaOrchestrator.enable = lib.mkDefault true;  # Fixed: now uses agenix
    assertions = [];
  };

}
