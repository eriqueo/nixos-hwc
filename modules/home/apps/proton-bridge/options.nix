# modules/home/apps/proton-bridge/options.nix
{ lib, ... }:

{
  options.features.protonBridge.enable =
    lib.mkEnableOption "Enable ProtonMail Bridge (encrypted email)";
}