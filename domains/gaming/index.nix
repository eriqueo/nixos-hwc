# domains/gaming/index.nix
#
# Gaming Domain - Emulation and game streaming services
#
# NAMESPACE: hwc.gaming.{retroarch,webdav}.*
#
# USED BY:
#   - machines/home/config.nix

{ lib, config, pkgs, ... }:

{
  imports = [
    ./retroarch/index.nix
    ./webdav/index.nix
  ];

  options.hwc.gaming.steam.enable = lib.mkEnableOption "Steam with declarative Proton-GE";
  config.programs.steam = lib.mkIf config.hwc.gaming.steam.enable {
    enable = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };
}
