# domains/ai/profiles/options.nix
#
# Hardware profile selection for AI workloads

{ lib, ... }:

{
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
}
