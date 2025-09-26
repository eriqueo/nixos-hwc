{ lib, pkgs, config, ... }:
let
  enabled  = config.hwc.home.apps.aerc.enable or false;

  cfgPart   = import ./parts/config.nix   { inherit lib pkgs config; };
  bindsPart = import ./parts/behavior.nix { inherit lib pkgs config; };
  sessPart  = import ./parts/session.nix  { inherit lib pkgs config; };
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf enabled {
    # ok to use `or` here because it's attribute selection
    home.packages     = (cfgPart.packages or []) ++ (sessPart.packages or []);
    home.file         = (cfgPart.files "") // (bindsPart.files "");
    home.shellAliases = (sessPart.shellAliases or {});
  };
}
