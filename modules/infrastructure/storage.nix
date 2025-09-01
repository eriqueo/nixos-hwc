# nixos-hwc/modules/infrastructure/storage.nix
#
# STORAGE - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.infrastructure.storage.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/infrastructure/storage.nix
#
# USAGE:
#   hwc.infrastructure.storage.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.storage;
  paths = config.hwc.paths;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.storage = {
    hot = {
      enable = lib.mkEnableOption "Hot storage tier";
      
      path = lib.mkOption {
        type = lib.types.path;
        default = "/mnt/hot";
        description = "Hot storage mount point";
      };
      
      device = lib.mkOption {
        type = lib.types.str;
        default = "/dev/disk/by-uuid/YOUR-UUID-HERE";
        description = "Device UUID";
      };
      
      fsType = lib.mkOption {
        type = lib.types.str;
        default = "ext4";
        description = "Filesystem type";
      };
    };
    
    media = {
      enable = lib.mkEnableOption "Media storage";
      
      path = lib.mkOption {
        type = lib.types.path;
        default = "/mnt/media";
        description = "Media storage mount point";
      };
      
      directories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "movies" "tv" "music" "books" "photos"
          "downloads" "incomplete" "blackhole"
        ];
        description = "Media subdirectories to create";
      };
    };
    
    backup = {
      enable = lib.mkEnableOption "Backup storage";
      
      path = lib.mkOption {
        type = lib.types.path;
        default = "/mnt/backup";
        description = "Backup storage path";
      };
    };
  };
  

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkMerge [
    (lib.mkIf cfg.hot.enable {
      fileSystems."${cfg.hot.path}" = {
        device = cfg.hot.device;
        fsType = cfg.hot.fsType;
        options = [ "defaults" "noatime" ];
      };
      
      systemd.tmpfiles.rules = [
        "d ${cfg.hot.path} 0755 root root -"
      ];
    })
    
    (lib.mkIf cfg.media.enable {
      systemd.tmpfiles.rules = 
        [ "d ${cfg.media.path} 0755 root root -" ] ++
        (map (dir: "d ${cfg.media.path}/${dir} 0775 media media -") cfg.media.directories);
      
      users.groups.media = {};
    })
    
    (lib.mkIf cfg.backup.enable {
      systemd.tmpfiles.rules = [
        "d ${cfg.backup.path} 0750 root root -"
      ];
    })
  ];
}
