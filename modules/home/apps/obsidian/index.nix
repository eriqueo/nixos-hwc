# modules/home/apps/obsidian/index.nix
{ config, lib, pkgs, ... }:

{
  imports = [
    ./options.nix
  ];

  config = lib.mkIf (config.features.obsidian.enable or false) {
    home.packages = with pkgs; [
      obsidian
    ];
  };
}