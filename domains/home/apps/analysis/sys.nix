{ config, lib, ... }:

let
  inherit (lib) mkIf;
in {
  options.hwc.system.apps.analysis = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable system-level support for analysis tool (e.g., for system packages if needed).";
    };
  };

  config = lib.mkIf config.hwc.system.apps.analysis.enable {
    # System packages if required (e.g., for non-Home use)
    environment.systemPackages = [];  # Empty for now; add if needed
  };
}
