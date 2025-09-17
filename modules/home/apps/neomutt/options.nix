# modules/home/apps/neomutt/options.nix
{ lib, ... }:

{
  options.features.neomutt.enable =
    lib.mkEnableOption "Enable NeoMutt (command-line email client)";
}