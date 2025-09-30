# HWC Charter Module/domains/infrastructure/user-hardware-access.nix
#
# USER HARDWARE ACCESS - Infrastructure layer for hardware permissions and directory setup
# Provides system-level user groups, tmpfiles rules, and hardware access permissions
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.* (modules/system/paths.nix)
#   - config.hwc.home.user.name (modules/home/eric.nix)
#
# USED BY (Downstream):
#   - profiles/*.nix (enables via hwc.infrastructure.hardware.permissions.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/infrastructure/user-hardware-access.nix
#
# USAGE:
#   hwc.infrastructure.hardware.permissions.enable = true;
#   hwc.infrastructure.hardware.permissions.username = "eric";

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.hardware.permissions;
  usersCfg = config.hwc.system.users;
  paths = config.hwc.paths;
in {
  #============================================================================
  # IMPLEMENTATION - User hardware access permissions
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

    # Hardware groups are created above; user group assignment handled in user domain
 
  };
}
