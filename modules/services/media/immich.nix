# nixos-hwc/modules/services/media/immich.nix
#
# IMMICH - Photo and video management service
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.services.immich.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/services/media/immich.nix
#
# USAGE:
#   hwc.services.immich.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:

with lib;

{
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.services.immich = {
    enable = mkEnableOption "Immich photo and video management service";
  };


  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = mkIf config.hwc.services.immich.enable {
    # TODO: Implement Immich service configuration
    warnings = [ "Immich service is not yet implemented" ];
  };
}
