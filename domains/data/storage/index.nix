{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.data.storage;
in
{
  # OPTIONS
  options.hwc.data.storage = {
    enable = lib.mkEnableOption "HWC storage automation services";

    cleanup = {
      enable = lib.mkEnableOption "media cleanup service";
      schedule = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "Schedule for cleanup service (systemd calendar format)";
      };
      retentionDays = lib.mkOption {
        type = lib.types.int;
        default = 7;
        description = "Number of days to keep temporary files";
      };
      paths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "${config.hwc.paths.hot.root}/processing/sonarr-temp"
          "${config.hwc.paths.hot.root}/processing/radarr-temp"
          "${config.hwc.paths.hot.root}/processing/lidarr-temp"
          "${config.hwc.paths.hot.downloads}/incomplete"
          "/var/tmp/hwc"
          "/var/cache/hwc"
        ];
        description = "Paths to clean up temporary files from";
      };
    };

    monitoring = {
      enable = lib.mkEnableOption "storage monitoring service";
      alertThreshold = lib.mkOption {
        type = lib.types.int;
        default = 85;
        description = "Storage usage percentage to trigger alerts";
      };
    };
  };

  imports = [
    ./parts/cleanup.nix
    ./parts/monitoring.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # No validation required - paths.nix always provides non-null paths
  };
}