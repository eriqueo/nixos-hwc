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
  options.hwc.ai.profiles = {
    selected = lib.mkOption {
      type = lib.types.enum ["auto" "laptop" "server" "cpu-only"];
      default = "auto";
      description = ''
        Hardware profile selection for AI workloads.

        - auto: Detect profile based on RAM and GPU presence
        - laptop: Conservative limits, thermal-aware (battery laptops)
        - server: Relaxed limits, assumes datacenter cooling
        - cpu-only: Minimal resources, no GPU acceleration
      '';
    };

    detection.ramThresholdGB = lib.mkOption {
      type = lib.types.int;
      default = 16;
      description = ''
        RAM threshold in GB for auto profile detection.
        Systems with >= this amount are detected as 'server' profile.
      '';
    };
  };

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
