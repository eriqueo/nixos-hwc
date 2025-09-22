# nixos-h../domains/infrastructure/storage.nix
#
# STORAGE - Storage infrastructure management with external drive detection
# Provides hot storage, media storage, backup storage, and external drive auto-mounting
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.* (modules/system/paths.nix)
#   - udev for external drive detection
#
# USED BY (Downstream):
#   - profiles/*.nix (enables via hwc.infrastructure.storage.enable)
#   - modules/services/backup/user-backup.nix (uses backup storage)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix or profiles/server.nix: ../domains/infrastructure/storage.nix
#
# USAGE:
#   hwc.infrastructure.storage.backup.enable = true;
#   hwc.infrastructure.storage.backup.externalDrive.autoMount = true;

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.infrastructure.hardware.storage;
  paths = config.hwc.paths;
  
  # External drive mount script
  mountScript = pkgs.writeScriptBin "mount-backup-drive" ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    DEVICE="$1"
    ACTION="$2"  # add or remove
    
    log_info() { 
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" | ${pkgs.systemd}/bin/systemd-cat -t mount-backup-drive
    }
    log_error() { 
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | ${pkgs.systemd}/bin/systemd-cat -t mount-backup-drive -p err
    }
    
    send_notification() {
      local message="$1"
      local icon="$2"
      local urgency="$3"
      
      ${lib.optionalString (cfg.backup.externalDrive.notificationUser != null) ''
        if command -v notify-send >/dev/null 2>&1; then
          sudo -u "${cfg.backup.externalDrive.notificationUser}" DISPLAY=:0 \
            ${pkgs.libnotify}/bin/notify-send "Backup Drive" "$message" \
            --icon="$icon" --urgency="$urgency" || true
        fi
      ''}
    }
    
    if [[ "$ACTION" == "add" ]]; then
      log_info "External drive detected: $DEVICE"
      
      # Check if device has the expected label
      LABEL=$(${pkgs.util-linux}/bin/blkid -o value -s LABEL "$DEVICE" 2>/dev/null || echo "")
      FSTYPE=$(${pkgs.util-linux}/bin/blkid -o value -s TYPE "$DEVICE" 2>/dev/null || echo "")
      
      log_info "Device $DEVICE: Label='$LABEL', FSType='$FSTYPE'"
      
      # Check if filesystem is supported
      if [[ ! " ${lib.concatStringsSep " " cfg.backup.externalDrive.fsTypes} " =~ " $FSTYPE " ]]; then
        log_error "Unsupported filesystem type: $FSTYPE"
        send_notification "Unsupported backup drive filesystem: $FSTYPE" "dialog-error" "normal"
        exit 1
      fi
      
      # Create mount point if it doesn't exist
      mkdir -p "${cfg.backup.path}"
      
      # Check if already mounted
      if mountpoint -q "${cfg.backup.path}"; then
        log_info "Backup mount point already in use"
        send_notification "Backup drive mount point already in use" "dialog-warning" "normal"
        exit 1
      fi
      
      # Mount the device
      if mount -t "$FSTYPE" -o "${lib.concatStringsSep "," cfg.backup.externalDrive.mountOptions}" "$DEVICE" "${cfg.backup.path}"; then
        log_info "Successfully mounted $DEVICE at ${cfg.backup.path}"
        
        # Set appropriate permissions
        chmod 755 "${cfg.backup.path}"
        
        send_notification "Backup drive mounted successfully" "drive-removable-media" "normal"
        
        # Create backups directory if it doesn't exist
        mkdir -p "${cfg.backup.path}/backups"
        chmod 755 "${cfg.backup.path}/backups"
      else
        log_error "Failed to mount $DEVICE"
        send_notification "Failed to mount backup drive" "dialog-error" "critical"
        exit 1
      fi
      
    elif [[ "$ACTION" == "remove" ]]; then
      log_info "External drive removal detected"
      
      # Check if our backup mount point is mounted
      if mountpoint -q "${cfg.backup.path}"; then
        log_info "Unmounting backup drive from ${cfg.backup.path}"
        
        if umount "${cfg.backup.path}"; then
          log_info "Successfully unmounted backup drive"
          send_notification "Backup drive safely unmounted" "drive-removable-media" "normal"
        else
          log_error "Failed to unmount backup drive"
          send_notification "Failed to unmount backup drive" "dialog-error" "critical"
          exit 1
        fi
      fi
    fi
  '';
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.infrastructure.hardware.storage = {
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
      enable = lib.mkEnableOption "Backup storage infrastructure";
      
      path = lib.mkOption {
        type = lib.types.path;
        default = "/mnt/backup";
        description = "Backup storage mount point";
      };
      
      # External drive detection and auto-mounting
      externalDrive = {
        autoMount = lib.mkEnableOption "automatic external drive mounting for backups";
        
        label = lib.mkOption {
          type = lib.types.str;
          default = "BACKUP";
          description = "Expected filesystem label for backup drives";
        };
        
        fsTypes = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "ext4" "ntfs" "exfat" "vfat" ];
          description = "Supported filesystem types for external drives";
        };
        
        mountOptions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "defaults" "noatime" "user" "exec" ];
          description = "Mount options for external drives";
        };
        
        notificationUser = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = config.hwc.system.users.user.name or null;
          description = "User to notify when drives are mounted/unmounted";
        };
      };
    };
  };
  

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkMerge [
    # Hot storage configuration
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
    
    # Media storage configuration
    (lib.mkIf cfg.media.enable {
      systemd.tmpfiles.rules = 
        [ "d ${cfg.media.path} 0755 root root -" ] ++
        (map (dir: "d ${cfg.media.path}/${dir} 0775 media media -") cfg.media.directories);
      
      users.groups.media = {};
    })
    
    # Basic backup storage
    (lib.mkIf cfg.backup.enable {
      systemd.tmpfiles.rules = [
        "d ${cfg.backup.path} 0750 root root -"
      ];
      
      # Install mount script
      environment.systemPackages = lib.optionals cfg.backup.externalDrive.autoMount [
        mountScript
      ];
    })
    
    # External drive auto-mounting
    (lib.mkIf (cfg.backup.enable && cfg.backup.externalDrive.autoMount) {
      # Install required packages
      environment.systemPackages = with pkgs; [
        util-linux      # blkid, mount, umount
        libnotify       # notifications
      ];
      
      # udev rules for external drive detection
      services.udev.extraRules = ''
        # Auto-mount external backup drives
        # USB storage devices
        ACTION=="add", KERNEL=="sd[b-z][0-9]", SUBSYSTEMS=="usb", \
          ENV{ID_FS_TYPE}=="${lib.concatStringsSep "|" cfg.backup.externalDrive.fsTypes}", \
          RUN+="${mountScript}/bin/mount-backup-drive %k add"
        
        # Remove handling
        ACTION=="remove", KERNEL=="sd[b-z][0-9]", SUBSYSTEMS=="usb", \
          RUN+="${mountScript}/bin/mount-backup-drive %k remove"
        
        # SATA/NVME external drives (USB adapters)
        ACTION=="add", KERNEL=="nvme[0-9]n[0-9]p[0-9]", SUBSYSTEMS=="usb", \
          ENV{ID_FS_TYPE}=="${lib.concatStringsSep "|" cfg.backup.externalDrive.fsTypes}", \
          RUN+="${mountScript}/bin/mount-backup-drive %k add"
      '';
      
      # Allow users to mount/unmount
      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id.indexOf("org.freedesktop.udisks2.") == 0 &&
              subject.isInGroup("users")) {
            return polkit.Result.YES;
          }
        });
      '';
      
      # Ensure mount point exists
      systemd.tmpfiles.rules = [
        "d ${cfg.backup.path} 0755 root root -"
      ];
    })
  ];
}
