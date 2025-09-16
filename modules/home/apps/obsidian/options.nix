# modules/home/apps/obsidian/options.nix
{ lib, ... }:

{
  options.features.obsidian.enable =
    lib.mkEnableOption "Enable Obsidian knowledge management app";
}