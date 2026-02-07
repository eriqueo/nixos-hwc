# domains/infrastructure/index.nix
{ config, lib, ... }:
let
  dir = builtins.readDir ./.;
  subds = lib.filterAttrs (n: t: t == "directory") dir;
  subIndex = lib.pipe (lib.attrNames subds) [
    (ns: lib.filter (n: builtins.pathExists (./. + "/${n}/index.nix")) ns)
    (ns: lib.map (n: ./. + "/${n}/index.nix") ns)
  ];
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ] ++ subIndex;
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};

  #==========================================================================
  # VALIDATION
  #==========================================================================
    config.assertions = lib.mkIf (config ? enable && config.enable) [];

}
