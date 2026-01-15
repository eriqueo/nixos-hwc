{ lib, ... }:

let
  inherit (lib) mkOption types;
in {
  options.hwc.system.apps.analysis = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable system-level support for analysis tool (e.g., for system packages if needed).";
    };
  };

  config = mkIf config.hwc.system.apps.analysis.enable {
    # System packages if required (e.g., for non-Home use)
    environment.systemPackages = [];  # Empty for now; add if needed
  };
}
