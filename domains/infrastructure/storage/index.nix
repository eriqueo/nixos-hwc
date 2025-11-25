# domains/infrastructure/storage/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.infrastructure.storage;
  paths = config.hwc.paths;

  mountScript = pkgs.writeScriptBin "mount-backup-drive" ''
    #!/usr/bin/env bash
    set -euo pipefail

    DEVICE="$1"
    ACTION="$2"

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

      LABEL=$(${pkgs.util-linux}/bin/blkid -o value -s LABEL "$DEVICE" 2>/dev/null || echo "")
      FSTYPE=$(${pkgs.util-linux}/bin/blkid -o value -s TYPE "$DEVICE" 2>/dev/null || echo "")

      log_info "Device $DEVICE: Label='$LABEL', FSType='$FSTYPE'"

      if [[ ! " ${lib.concatStringsSep " " cfg.backup.externalDrive.fsTypes} " =~ " $FSTYPE " ]]; then
        log_error "Unsupported filesystem type: $FSTYPE"
        send_notification "Unsupported backup drive filesystem: $FSTYPE" "dialog-error" "normal"
        exit 1
      fi

      mkdir -p "${cfg.backup.path}"

      if mountpoint -q "${cfg.backup.path}"; then
        log_info "Backup mount point already in use"
        send_notification "Backup drive mount point already in use" "dialog-warning" "normal"
        exit 1
      fi

      if mount -t "$FSTYPE" -o "${lib.concatStringsSep "," cfg.backup.externalDrive.mountOptions}" "$DEVICE" "${cfg.backup.path}"; then
        log_info "Successfully mounted $DEVICE at ${cfg.backup.path}"
        chmod 755 "${cfg.backup.path}"
        send_notification "Backup drive mounted successfully" "drive-removable-media" "normal"
        mkdir -p "${cfg.backup.path}/backups"
        chmod 755 "${cfg.backup.path}/backups"
      else
        log_error "Failed to mount $DEVICE"
        send_notification "Failed to mount backup drive" "dialog-error" "critical"
        exit 1
      fi

    elif [[ "$ACTION" == "remove" ]]; then
      log_info "External drive removal detected"

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
  imports = [ ./options.nix ];

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

      users.groups.media = { gid = 1000; };
    })

    (lib.mkIf cfg.backup.enable {
      systemd.tmpfiles.rules = [
        "d ${cfg.backup.path} 0750 root root -"
      ];

      environment.systemPackages = lib.optionals cfg.backup.externalDrive.autoMount [
        mountScript
      ];
    })

    (lib.mkIf (cfg.backup.enable && cfg.backup.externalDrive.autoMount) {
      environment.systemPackages = with pkgs; [
        util-linux
        libnotify
      ];

      services.udev.extraRules = ''
        ACTION=="add", KERNEL=="sd[b-z][0-9]", SUBSYSTEMS=="usb", \
          ENV{ID_FS_TYPE}=="${lib.concatStringsSep "|" cfg.backup.externalDrive.fsTypes}", \
          RUN+="${mountScript}/bin/mount-backup-drive %k add"

        ACTION=="remove", KERNEL=="sd[b-z][0-9]", SUBSYSTEMS=="usb", \
          RUN+="${mountScript}/bin/mount-backup-drive %k remove"

        ACTION=="add", KERNEL=="nvme[0-9]n[0-9]p[0-9]", SUBSYSTEMS=="usb", \
          ENV{ID_FS_TYPE}=="${lib.concatStringsSep "|" cfg.backup.externalDrive.fsTypes}", \
          RUN+="${mountScript}/bin/mount-backup-drive %k add"
      '';

      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id.indexOf("org.freedesktop.udisks2.") == 0 &&
              subject.isInGroup("users")) {
            return polkit.Result.YES;
          }
        });
      '';

      systemd.tmpfiles.rules = [
        "d ${cfg.backup.path} 0755 root root -"
      ];
    })
  ];
}
