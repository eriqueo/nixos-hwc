{ config, lib, pkgs, osConfig ? {}, ...}:

let
  cfg = config.hwc.home.apps.thunderbird;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.thunderbird = {
    enable = lib.mkEnableOption "Full-featured e-mail client";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      thunderbird
    ];
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
}