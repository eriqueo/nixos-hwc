# domains/system/services/monitoring/options.nix
#
# System monitoring with ntfy integration
# - Disk space monitoring (hourly timer)
# - Service failure notifications (OnFailure handler)
# - NixOS rebuild notifications (manual wrapper)

{ lib, ... }:

{
  options.hwc.system.services.monitoring = {
    enable = lib.mkEnableOption "Enable system monitoring with ntfy notifications";

    diskSpace = {
      enable = lib.mkEnableOption "Enable disk space monitoring" // { default = true; };

      frequency = lib.mkOption {
        type = lib.types.str;
        default = "hourly";
        description = "How often to check disk space (systemd calendar format)";
      };

      criticalThreshold = lib.mkOption {
        type = lib.types.int;
        default = 95;
        description = "Disk usage percentage for critical alerts (P5)";
      };

      warningThreshold = lib.mkOption {
        type = lib.types.int;
        default = 80;
        description = "Disk usage percentage for warnings (P4)";
      };

      filesystems = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "/" "/home" ];
        description = "List of mount points to monitor";
      };
    };

    serviceFailures = {
      enable = lib.mkEnableOption "Enable service failure notifications" // { default = true; };

      monitoredServices = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Services to attach OnFailure handlers to";
      };
    };
  };
}
