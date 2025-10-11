# domains/home/apps/86box/options.nix
{ lib, pkgs, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.home.apps._86box = {
    enable = mkEnableOption "86Box PC emulator";

    withRoms = mkOption {
      type = types.bool;
      default = true;
      description = "Include ROM files package";
    };

    configDir = mkOption {
      type = types.str;
      default = "~/.config/86Box";
      description = "Configuration directory for 86Box";
    };

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "86Box package to use (auto-selected based on withRoms if null)";
    };
  };
}
