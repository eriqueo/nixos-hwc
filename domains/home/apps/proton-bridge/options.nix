# modules/home/apps/proton-bridge/options.nix
{ lib, ... }:

{
  options.hwc.home.apps.protonBridge.enable =
    lib.mkEnableOption "Enable ProtonMail Bridge (encrypted email)";
}