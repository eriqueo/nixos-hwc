# modules/home/apps/index.nix
{ lib, osConfig ? {}, ... }:
let
  dir = builtins.readDir ./.;
  appDirs =
    lib.filter (n: let d = dir.${n}; in d == "directory" && builtins.pathExists (./. + "/${n}/index.nix"))
      (lib.attrNames dir);

  # optional: exclude scratch or "multi" scaffolding if you don't want it auto-loaded
  appDirsWanted = lib.filter (n: !(lib.hasSuffix "-bak" n) && n != "hyprland-new" && !(lib.hasPrefix "." n)) appDirs;

  appImports = map (n: ./. + "/${n}/index.nix") (lib.sort (a: b: a < b) appDirsWanted);
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ] ++ appImports;

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};

}
