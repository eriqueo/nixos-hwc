{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.herdr;
  herdrPkg =
    if cfg.package != null
    then cfg.package
    else pkgs.callPackage ./parts/package.nix { };
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    home.packages = [ herdrPkg ];

    assertions = [
      {
        assertion = herdrPkg != null;
        message   = "hwc.home.apps.herdr: package must be non-null";
      }
    ];
  };
}
