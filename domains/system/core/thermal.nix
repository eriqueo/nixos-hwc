# THERMAL - System thermal management and power profile configuration
{ config, lib, ... }:

let
  cfg = config.hwc.system.core.thermal;
in {
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    services.thermald.enable = lib.mkIf cfg.disableIncompatibleServices (lib.mkForce false);

    services.power-profiles-daemon.enable = lib.mkIf (cfg.powerManagement.enable && cfg.powerManagement.service == "power-profiles-daemon") true;

    services.tlp.enable = lib.mkForce false;

    boot.blacklistedKernelModules = cfg.blacklistedModules;

    assertions = [
      {
        assertion = !(cfg.powerManagement.enable && cfg.powerManagement.service == "power-profiles-daemon" && config.services.tlp.enable);
        message = "Cannot enable both power-profiles-daemon and TLP simultaneously";
      }
      {
        assertion = !(cfg.powerManagement.enable && cfg.powerManagement.service == "tlp" && config.services.power-profiles-daemon.enable);
        message = "Cannot enable both TLP and power-profiles-daemon simultaneously";
      }
    ];
  };
}
