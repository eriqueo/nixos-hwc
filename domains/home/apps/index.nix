# domains/home/apps/index.nix
{ lib, osConfig ? {}, ... }:
let
  dir = builtins.readDir ./.;
  appDirs =
    lib.filter (n: let d = dir.${n}; in d == "directory" && builtins.pathExists (./. + "/${n}/index.nix"))
      (lib.attrNames dir);

  # exclude dotted scratch dirs from auto-load
  appDirsWanted = lib.filter (n: !(lib.hasPrefix "." n)) appDirs;

  appImports = map (n: ./. + "/${n}/index.nix") (lib.sort (a: b: a < b) appDirsWanted);
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = appImports;

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};

}
