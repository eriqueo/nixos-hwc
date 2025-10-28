# modules/server/storage/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.services.storage = {
    enable = mkEnableOption "HWC storage automation services";

    cleanup = {
      enable = mkEnableOption "media cleanup service";
      schedule = mkOption {
        type = types.str;
        default = "daily";
        description = "Schedule for cleanup service (systemd calendar format)";
      };
      retentionDays = mkOption {
        type = types.int;
        default = 7;
        description = "Number of days to keep temporary files";
      };
      paths = mkOption {
        type = types.listOf types.str;
        default = [
          "/mnt/hot/processing/sonarr-temp"
          "/mnt/hot/processing/radarr-temp"
          "/mnt/hot/processing/lidarr-temp"
          "/mnt/hot/downloads/incomplete"
          "/var/tmp/hwc"
          "/var/cache/hwc"
        ];
        description = "Paths to clean up temporary files from";
      };
    };

    monitoring = {
      enable = mkEnableOption "storage monitoring service";
      alertThreshold = mkOption {
        type = types.int;
        default = 85;
        description = "Storage usage percentage to trigger alerts";
      };
    };
  };
}