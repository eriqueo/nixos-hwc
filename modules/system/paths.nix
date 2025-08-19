{ lib, config, ... }:
{
  options.hwc.paths = {
    # Remove 'root' - never used, confusing

    # Storage tiers - make optionals since not all machines have all tiers
    hot = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;  # Machine must explicitly set if they have it
      description = "Hot storage (SSD) - fast tier";
    };

    media = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;  # Not all machines serve media
      description = "Media storage (HDD) - bulk tier";
    };

    cold = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;  # Optional archive tier
      description = "Cold storage - archive tier";
    };

    backup = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;  # Not all machines do backups
      description = "Backup storage";
    };

    # System paths - these always exist
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
  };

  config = {
    # Only create directories that are actually set
    systemd.tmpfiles.rules = [
      "d ${config.hwc.paths.state} 0755 root root -"
      "d ${config.hwc.paths.cache} 0755 root root -"
      "d ${config.hwc.paths.logs} 0755 root root -"
    ] ++ lib.optional (config.hwc.paths.hot != null)
      "d ${config.hwc.paths.hot} 0755 root root -"
    ++ lib.optional (config.hwc.paths.media != null)
      "d ${config.hwc.paths.media} 0775 root media -";  # Note: media group
  };
}
