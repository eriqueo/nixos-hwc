# nixos-hwc/profiles/ai.nix
#
# Profile: AI Services (Orchestration Only)
# Aggregates AI service modules and sets high-level defaults.
# No hardware logic or user management here (Charter v3).
#
# DEPENDENCIES (Upstream):
#   - ../domains/server/ai/ollama.nix
#   - modules/infrastructure/hardware/gpu.nix (indirectly; services consume hwc.infrastructure.hardware.gpu.accel)
#
# USED BY (Downstream):
#   - machines/*/config.nix  (enable/override service facts per machine)
#
# IMPORTS REQUIRED IN:
#   - machines/*/config.nix: imports = [ ../../profiles/ai.nix ];
#
# USAGE:
#   # This profile sets defaults; machines can override:
#   #   hwc.services.ollama.enable = true;
#   #   hwc.services.ollama.models = [ "llama3:8b" ... ];
#   # GPU use is inferred from hwc.infrastructure.hardware.gpu.accel via modules/infrastructure/hardware/gpu.nix.

{ lib, ... }:

{
  #==========================================================================
  # BASE SYSTEM - Critical for machine functionality
  #==========================================================================
  imports = [
    ../domains/server/ai/ollama/ollama.nix
    # ../domains/server/ai/ai-bible/ai-bible.nix  # (optional future service)
  ];

  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================
  hwc.services.ollama = {
    enable = lib.mkDefault true;              # profile turns it on by default
    # No 'enableGpu' here—service consumes hwc.infrastructure.hardware.gpu.accel from infra module.
    models = lib.mkDefault [ "llama3:8b" "codellama:13b" ];
  };

  # Example (commented) placeholder for other AI services:
  # hwc.services.aiBible = {
  #   enable = lib.mkDefault false;
  #   features = {
  #     autoGeneration = lib.mkDefault true;
  #     llmIntegration = lib.mkDefault true;
  #   };
  #   llm = {
  #     provider = lib.mkDefault "ollama";
  #     model    = lib.mkDefault "llama3:8b";
  #   };
  # };
}
