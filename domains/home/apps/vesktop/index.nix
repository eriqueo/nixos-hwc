# domains/home/apps/vesktop/index.nix
{ config, lib, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.apps.vesktop;
in
{
  # OPTIONS
  options.hwc.home.apps.vesktop = {
    enable = lib.mkEnableOption "Vesktop Discord client";
  };

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
    programs.vesktop.enable = true;

    # VALIDATION
    assertions = [
      {
        assertion = config.programs.vesktop.enable;
        message = "programs.vesktop must remain enabled when hwc.home.apps.vesktop is enabled";
      }
    ];
  };
}
