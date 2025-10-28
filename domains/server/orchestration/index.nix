{ ... }:
{
  imports = [
    ./media-orchestrator.nix
  ];

  # Enable media orchestrator by default for server
  # hwc.server.orchestration.mediaOrchestrator.enable = true;  # Disabled: sops/agenix conflict
}