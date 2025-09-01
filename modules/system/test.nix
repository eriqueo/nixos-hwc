# nixos-hwc/modules/system/test.nix
#
# TEST - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.system.test.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/system/test.nix
#
# USAGE:
#   hwc.system.test.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, ... }:
{
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.test = {
    enable = lib.mkEnableOption "Test module";
  };
  

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf config.hwc.test.enable {
    environment.etc."nixos-refactor-test.txt".text = "Working!";
  };
}
