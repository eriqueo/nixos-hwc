# domains/infrastructure/storage/options.nix
{ lib, config, ... }:

let
  t = lib.types;
in
{
  options.hwc.infrastructure.storage = {
    hot = {
      enable = lib.mkEnableOption "Hot storage tier";

      path = lib.mkOption {
        type = t.path;
        default = if config.hwc.paths.hot.root != null then config.hwc.paths.hot.root else "/mnt/hot";
        description = "Hot storage mount point";
      };

      device = lib.mkOption {
        type = t.str;
        default = "/dev/disk/by-uuid/YOUR-UUID-HERE";
        description = "Device UUID";
      };

      fsType = lib.mkOption {
        type = t.str;
        default = "ext4";
        description = "Filesystem type";
      };
    };

    media = {
      enable = lib.mkEnableOption "Media storage";

      path = lib.mkOption {
        type = t.path;
        default = if config.hwc.paths.media.root != null then config.hwc.paths.media.root else "/mnt/media";
        description = "Media storage mount point";
      };

      directories = lib.mkOption {
        type = t.listOf t.str;
        default = [
          "movies" "tv" "music" "books" "photos"
          "downloads" "incomplete" "blackhole"
        ];
        description = "Media subdirectories to create";
      };
    };

    backup = {
      enable = lib.mkEnableOption "Backup storage infrastructure";

      path = lib.mkOption {
        type = t.path;
        default = if config.hwc.paths.backup != null then config.hwc.paths.backup else "/mnt/backup";
        description = "Backup storage mount point";
      };

      externalDrive = {
        autoMount = lib.mkEnableOption "automatic external drive mounting for backups";

        label = lib.mkOption {
          type = t.str;
          default = "BACKUP";
          description = "Expected filesystem label for backup drives";
        };

        fsTypes = lib.mkOption {
          type = t.listOf t.str;
          default = [ "ext4" "ntfs" "exfat" "vfat" ];
          description = "Supported filesystem types for external drives";
        };

        mountOptions = lib.mkOption {
          type = t.listOf t.str;
          default = [ "defaults" "noatime" "user" "exec" ];
          description = "Mount options for external drives";
        };

        notificationUser = lib.mkOption {
          type = t.nullOr t.str;
          default = config.hwc.system.users.user.name or null;
          description = "User to notify when drives are mounted/unmounted";
        };
      };
    };
  };
}
