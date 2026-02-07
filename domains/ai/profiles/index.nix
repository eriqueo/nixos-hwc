# domains/ai/profiles/index.nix
#
# Hardware profile detection and defaults export for AI workloads

{ config, lib, ... }:

let
  profiles = import ./parts/definitions.nix { inherit config lib; };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {
    # Export profile info for other modules via _module.args
    _module.args.aiProfile = profiles.activeProfile;
    _module.args.aiProfileName = profiles.detectedProfile;

    # Make detection visible via warnings (not assertions)
    warnings = [
      "AI Profile: ${profiles.detectedProfile} (GPU: ${profiles.hardware.gpuType}, RAM: ${toString profiles.hardware.totalRAM_GB}GB)"
    ];
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Profile detection is informational - no hard failures needed
}
