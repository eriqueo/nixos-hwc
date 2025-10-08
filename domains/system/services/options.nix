# domains/system/services/options.nix
#
# Consolidated options for system services subdomain
# Charter-compliant: ALL services options defined here

{ lib, config, ... }:

{
  #============================================================================
  # BEHAVIOR OPTIONS (Input devices & audio)
  #============================================================================
  options.hwc.system.services.behavior = {
    enable = lib.mkEnableOption "system input behavior and audio configuration";

    keyboard = {
      enable = lib.mkEnableOption "universal keyboard mapping";
      universalFunctionKeys = lib.mkEnableOption "standardize F-keys across all keyboards";
    };

    mouse = {
      enable = lib.mkEnableOption "universal mouse configuration";
    };

    touchpad = {
      enable = lib.mkEnableOption "universal touchpad configuration";
    };

    audio = {
      enable = lib.mkEnableOption "PipeWire audio system";
    };
  };
}
