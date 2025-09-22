{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.gluetun;
in
{
  imports = [
    ./options.nix
    ./sys.nix
    ./parts/config.nix
    ./parts/scripts.nix
    ./parts/pkgs.nix
    ./parts/lib.nix
  ];

  config = lib.mkIf cfg.enable { };
}
