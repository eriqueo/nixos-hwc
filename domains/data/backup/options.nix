# domains/server/backup/options.nix
#
# Consolidated options for server backup subdomain
# Charter-compliant: ALL backup options defined here

{ lib, config, ... }:

let
  userCfg = config.hwc.system;
in
{
  options.hwc.server.native.backup = {
    enable = lib.mkEnableOption "automated server backup (containers, databases, system)";
  };

  options.hwc.server.backup.user = {
    enable = lib.mkEnableOption "intelligent user data backup service";

    username = lib.mkOption {
      type = lib.types.str;
      default = userCfg.user.name or "eric";
      description = "Username to backup";
    };

    #==========================================================================
    # EXTERNAL DRIVE CONFIGURATION
    #==========================================================================
    externalDrive = {
      enable = lib.mkEnableOption "external drive backup (primary method)";

      mountPoint = lib.mkOption {
        type = lib.types.str;
        default = config.hwc.paths.backup or "/mnt/backup";
        description = "External drive mount point";
      };

      minSpaceGB = lib.mkOption {
        type = lib.types.ints.positive;
        default = 10;
        description = "Minimum free space required (GB) before attempting backup";
      };

      keepDays = lib.mkOption {
        type = lib.types.ints.positive;
        default = 30;
        description = "Days to keep old backups on external drive";
      };
    };

    #==========================================================================
    # PROTON DRIVE CONFIGURATION
    #==========================================================================
    protonDrive = {
      enable = lib.mkEnableOption "Proton Drive backup (fallback method)";

      configPath = lib.mkOption {
        type = lib.types.str;
        default = "/etc/rclone-proton.conf";
        description = "Path to rclone config file for Proton Drive";
      };

      useSecret = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use agenix secret for rclone config";
      };

      secretName = lib.mkOption {
        type = lib.types.str;
        default = "rclone-proton-config";
        description = "Agenix secret name for rclone config";
      };
    };

    #==========================================================================
    # SCHEDULING OPTIONS
    #==========================================================================
    schedule = {
      enable = lib.mkEnableOption "automatic backup scheduling";

      frequency = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "Backup frequency (systemd calendar format)";
      };

      randomDelay = lib.mkOption {
        type = lib.types.str;
        default = "1h";
        description = "Random delay to spread backup load";
      };
    };

    #==========================================================================
    # NOTIFICATION OPTIONS
    #==========================================================================
    notifications = {
      enable = lib.mkEnableOption "desktop notifications for backup status";
    };
  };
}