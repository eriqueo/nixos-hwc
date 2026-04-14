# domains/system/usb-automount.nix
#
# USB drive auto-mount with user-accessible permissions.
# Handles NTFS, exFAT, FAT32. Skips drives in /etc/fstab.
# Includes NTFS fixperms service for declared NTFS mounts.
#
# NAMESPACE: hwc.system.usb.*

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.usb;
  user = config.hwc.system.users.user.name;
  t = lib.types;

  usbAutoMount = pkgs.writeShellScript "usb-automount" ''
    set -euo pipefail
    [[ -z "''${1:-}" ]] && exit 1
    DEVICE="/dev/$1"

    # Skip drives managed declaratively (UUID present in /etc/fstab)
    UUID=$(${pkgs.util-linux}/bin/blkid -o value -s UUID "$DEVICE" 2>/dev/null || true)
    [[ -n "$UUID" ]] && grep -qiF "$UUID" /etc/fstab && exit 0

    FSTYPE=$(${pkgs.util-linux}/bin/blkid -o value -s TYPE "$DEVICE" 2>/dev/null || true)
    [[ -z "$FSTYPE" ]] && exit 0

    LABEL=$(${pkgs.util-linux}/bin/blkid -o value -s LABEL "$DEVICE" 2>/dev/null \
      | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '_')
    # Strip leading dots/underscores to prevent mounting at /mnt/.. etc.
    LABEL="''${LABEL##*([._])}"
    [[ -z "$LABEL" ]] && LABEL="usb-$(basename "$DEVICE")"

    # Skip if this device is already mounted
    ${pkgs.util-linux}/bin/findmnt -n "$DEVICE" >/dev/null 2>&1 && exit 0

    MOUNT="/mnt/$LABEL"
    mkdir -p "$MOUNT"
    trap '${pkgs.util-linux}/bin/mountpoint -q "$MOUNT" || rmdir "$MOUNT" 2>/dev/null || true' EXIT

    case "$FSTYPE" in
      ntfs|ntfs3)
        ${pkgs.util-linux}/bin/mount -t ntfs3 \
          -o uid=1000,gid=100,dmask=0000,fmask=0000,force,iocharset=utf8 \
          "$DEVICE" "$MOUNT"
        # NTFS Windows ACLs can map dirs to root — fix so user can delete
        ${pkgs.findutils}/bin/find "$MOUNT" -maxdepth 1 -not -user ${user} \
          -exec ${pkgs.coreutils}/bin/chown -R ${user}:users {} + 2>/dev/null || true
        ;;
      exfat)
        ${pkgs.util-linux}/bin/mount -t exfat \
          -o uid=1000,gid=100,dmask=0000,fmask=0000 \
          "$DEVICE" "$MOUNT"
        ;;
      vfat|fat32|fat)
        ${pkgs.util-linux}/bin/mount -t vfat \
          -o uid=1000,gid=100,dmask=0000,fmask=0000,codepage=437,iocharset=utf8 \
          "$DEVICE" "$MOUNT"
        ;;
    esac
  '';

  usbAutoUnmount = pkgs.writeShellScript "usb-autounmount" ''
    DEVICE="/dev/$1"
    TARGET=$(${pkgs.util-linux}/bin/findmnt -n -o TARGET "$DEVICE" 2>/dev/null || true)
    [[ -n "$TARGET" ]] && ${pkgs.util-linux}/bin/umount "$TARGET" 2>/dev/null || true
  '';

in
{
  options.hwc.system.usb = {
    autoMount.enable = lib.mkEnableOption "USB drive auto-mount via udev (NTFS/exFAT/FAT32)";

    ntfsFixperms = lib.mkOption {
      type = t.listOf (t.submodule {
        options = {
          mountPoint = lib.mkOption { type = t.str; description = "Mount point to fix permissions on"; };
          afterUnit = lib.mkOption { type = t.str; description = "systemd mount unit to trigger after"; };
        };
      });
      default = [];
      description = "NTFS mounts needing top-level permission fixup after mount";
    };
  };

  config = lib.mkMerge [
    # USB auto-mount udev rules
    (lib.mkIf cfg.autoMount.enable {
      services.udev.extraRules = lib.mkAfter ''
        # Auto-mount external USB drives at /mnt/<label>
        ACTION=="add", KERNEL=="sd[b-z][0-9]*", SUBSYSTEMS=="usb", ENV{ID_FS_TYPE}=="ntfs", \
          RUN+="${usbAutoMount} %k"
        ACTION=="add", KERNEL=="sd[b-z][0-9]*", SUBSYSTEMS=="usb", ENV{ID_FS_TYPE}=="ntfs3", \
          RUN+="${usbAutoMount} %k"
        ACTION=="add", KERNEL=="sd[b-z][0-9]*", SUBSYSTEMS=="usb", ENV{ID_FS_TYPE}=="exfat", \
          RUN+="${usbAutoMount} %k"
        ACTION=="add", KERNEL=="sd[b-z][0-9]*", SUBSYSTEMS=="usb", ENV{ID_FS_TYPE}=="vfat", \
          RUN+="${usbAutoMount} %k"
        ACTION=="remove", KERNEL=="sd[b-z][0-9]*", SUBSYSTEMS=="usb", \
          RUN+="${usbAutoUnmount} %k"
      '';
    })

    # NTFS fixperms services (one per declared mount)
    (lib.mkIf (cfg.ntfsFixperms != []) {
      systemd.services = lib.listToAttrs (map (fp:
        let
          safeName = lib.replaceStrings ["/"] ["-"] (lib.removePrefix "/" fp.mountPoint);
        in lib.nameValuePair "ntfs-fixperms-${safeName}" {
          description = "Fix NTFS directory ownership on ${fp.mountPoint}";
          after = [ fp.afterUnit ];
          wantedBy = [ fp.afterUnit ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "ntfs-fixperms-${safeName}" ''
              ${pkgs.findutils}/bin/find ${fp.mountPoint} -maxdepth 1 -not -user ${user} \
                -exec ${pkgs.coreutils}/bin/chown -R ${user}:users {} + 2>/dev/null || true
            '';
          };
        }
      ) cfg.ntfsFixperms);
    })
  ];
}
