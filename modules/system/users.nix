# nixos-hwc/modules/system/users.nix
#
# USERS - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.system.users.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/system/users.nix
#
# USAGE:
#   hwc.system.users.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:
{
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  users.users.eric = {
    isNormalUser = true;
    description = "Eric";
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
      "media"
      "video"
      "audio"
    ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here from your current config
    ];
  };

  # Media group for shared access
  users.groups.media = {};

  # Enable sudo
  security.sudo.wheelNeedsPassword = false;
}
