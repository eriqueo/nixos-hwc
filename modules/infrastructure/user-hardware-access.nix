# nixos-hwc/modules/infrastructure/user-hardware-access.nix
#
# USER HARDWARE ACCESS - Infrastructure layer for hardware permissions and directory setup
# Provides system-level user groups, tmpfiles rules, and hardware access permissions
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.* (modules/system/paths.nix)
#   - config.hwc.home.user.name (modules/home/eric.nix)
#
# USED BY (Downstream):
#   - profiles/*.nix (enables via hwc.infrastructure.userHardwareAccess.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/infrastructure/user-hardware-access.nix
#
# USAGE:
#   hwc.infrastructure.userHardwareAccess.enable = true;
#   hwc.infrastructure.userHardwareAccess.username = "eric";

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.userHardwareAccess;
  usersCfg = config.hwc.system.users;
  paths = config.hwc.paths;
in {

  #============================================================================
  # OPTIONS - User Hardware Access Configuration
  #============================================================================

  options.hwc.infrastructure.userHardwareAccess = {
    enable = lib.mkEnableOption "user hardware access permissions and system setup";

    username = lib.mkOption {
      type = lib.types.str;
      default = usersCfg.user.name or "eric";
      description = "Username for hardware access setup";
    };

    groups = {
      media = lib.mkEnableOption "media hardware groups (video, audio, render)";
      development = lib.mkEnableOption "development groups (docker, podman)";
      virtualization = lib.mkEnableOption "virtualization groups (libvirtd, kvm)";
      hardware = lib.mkEnableOption "hardware access groups (input, uucp, dialout)";
    };
  };

  #============================================================================
  # IMPLEMENTATION - Hardware Access and System Setup
  #============================================================================

  config = lib.mkIf cfg.enable {

    #=========================================================================
    # USER DIRECTORY PERMISSIONS AND OWNERSHIP
    #=========================================================================

    # User home directory ownership (using paths module)
    systemd.tmpfiles.rules = [
      "Z ${paths.user.home} - ${cfg.username} users - -"
      "Z ${paths.user.ssh} 0700 ${cfg.username} users - -" 
      "d ${paths.user.config} 0755 ${cfg.username} users -"
    ];

    #=========================================================================
    # HARDWARE ACCESS GROUPS CREATION
    #=========================================================================

    # Hardware group creation and user assignment
    users.groups = lib.mkIf cfg.groups.media {
      render = lib.mkForce { gid = 2002; };  # GPU rendering group
    };

    # Add hardware groups to user account
    users.users.${cfg.username}.extraGroups = lib.lists.flatten [
      (lib.optionals cfg.groups.media [ "video" "audio" "render" ])
      (lib.optionals cfg.groups.development [ "docker" "podman" ])
      (lib.optionals cfg.groups.virtualization [ "libvirtd" "kvm" ])
      (lib.optionals cfg.groups.hardware [ "input" "uucp" "dialout" ])
    ];

  };
}