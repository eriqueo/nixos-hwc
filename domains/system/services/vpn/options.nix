# FINAL, CORRECT file: domains/system/services/vpn/options.nix
{ lib, config, ... }:

{
  options.hwc.system.services.vpn = {
    enable = lib.mkEnableOption "Enable VPN services";

    protonvpn = {
      # This single toggle will activate the entire service.
      enable = lib.mkEnableOption "Enable ProtonVPN via the official CLI tool";
    };
  };
}
