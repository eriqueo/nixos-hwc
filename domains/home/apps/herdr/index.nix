{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.herdr;
  herdrPkg =
    if cfg.package != null
    then cfg.package
    else pkgs.callPackage ./parts/package.nix { };
in
{
  # OPTIONS
  options.hwc.home.apps.herdr = {
    enable = lib.mkEnableOption "herdr — terminal agent multiplexer (tmux for AI agents)";

    package = lib.mkOption {
      type        = lib.types.nullOr lib.types.package;
      default     = null;
      description = "Herdr package to use. If null, builds from upstream release binary via parts/package.nix.";
    };
  };

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
