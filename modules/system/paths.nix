{ lib, config, ... }:
{
  options.hwc.paths = {
    root = lib.mkOption {
      type = lib.types.path;
      default = "/";
      description = "System root";
    };

    hot = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/hot";
      description = "Hot storage (SSD)";
    };

    media = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/media";
      description = "Media storage (HDD)";
    };

    cold = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/cold";
      description = "Cold storage (Archive)";
    };

    state = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hwc";
      description = "Service state directory";
    };

    cache = lib.mkOption {
      type = lib.types.path;
      default = "/var/cache/hwc";
      description = "Cache directory";
    };

    logs = lib.mkOption {
      type = lib.types.path;
      default = "/var/log/hwc";
      description = "Log directory";
    };

    backup = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/backup";
      description = "Backup directory";
    };
  };

  config = {
    # Ensure base directories exist
    systemd.tmpfiles.rules = [
      "d ${config.hwc.paths.state} 0755 root root -"
      "d ${config.hwc.paths.cache} 0755 root root -"
      "d ${config.hwc.paths.logs} 0755 root root -"
    ];
  };
}
