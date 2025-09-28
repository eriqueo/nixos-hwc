# HWC Charter Module/domains/system/core/polkit.nix
#
# POLKIT - PolicyKit configuration and directory management
# Provides polkit directory structure and basic configuration
#
# DEPENDENCIES (Upstream):
#   - None (base system services)
#
# USED BY (Downstream):
#   - profiles/workstation.nix (enables via hwc.system.core.polkit.enable)
#
# IMPORTS REQUIRED IN:
#   - Automatically imported via modules/system/core/index.nix
#
# USAGE:
#   hwc.system.core.polkit.enable = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.core.polkit;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================

  options.hwc.system.core.polkit = {
    enable = lib.mkEnableOption "polkit directory management";

    createMissingDirectories = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create missing polkit rule directories to silence warnings";
    };
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================

  config = lib.mkIf cfg.enable {
    
    # Create missing polkit directories to silence error messages
    systemd.tmpfiles.rules = lib.mkIf cfg.createMissingDirectories [
      "d /usr/local/share/polkit-1/rules.d 0755 root root -"
      "d /run/polkit-1/rules.d             0755 root root -"
    ];

    # Enable polkit service
    security.polkit.enable = true;
  };
}