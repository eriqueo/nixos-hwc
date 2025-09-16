{ lib, config, pkgs, ... }:
let
  inherit (lib) mkOption mkEnableOption mkIf mkMerge types;
  shared = config.hwc.services.shared.lib;
  cfg = config.hwc.services.containers.soularr;
in
{
  imports = [
    ./sys.nix
  ./parts/sys.nix
    ./parts/config.nix
    ./parts/scripts.nix
    ./parts/pkgs.nix
    ./parts/lib.nix
  ];

  config = mkIf cfg.enable { };
}
