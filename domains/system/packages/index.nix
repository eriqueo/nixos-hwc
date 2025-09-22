# modules/system/packages/index.nix — aggregates system package definitions
{ lib, ... }:
let
  dir   = builtins.readDir ./.;
  files = lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n && n != "index.nix") dir;
  subds = lib.filterAttrs (_: t: t == "directory") dir;

  filePaths = lib.mapAttrsToList (n: _: ./. + "/${n}") files;
  subIndex  =
    lib.pipe (lib.attrNames subds) [
      (ns: lib.filter (n: builtins.pathExists (./. + "/${n}/index.nix")) ns)
      (ns: lib.map (n: ./. + "/${n}/index.nix") ns)
    ];
in
{
  imports = filePaths ++ subIndex;
}