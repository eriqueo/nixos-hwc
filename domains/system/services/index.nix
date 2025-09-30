# modules/system/services/index.nix — aggregates system service configuration
{ lib, ... }:
let
  dir   = builtins.readDir ./.;
  files = lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n && n != "index.nix" && n != "options.nix") dir;
  subds = lib.filterAttrs (n: t: t == "directory" && n != "parts") dir;

  filePaths = lib.mapAttrsToList (n: _: ./. + "/${n}") files;
  subIndex  =
    lib.pipe (lib.attrNames subds) [
      (ns: lib.filter (n: builtins.pathExists (./. + "/${n}/index.nix")) ns)
      (ns: lib.map (n: ./. + "/${n}/index.nix") ns)
    ];
in
{
  imports = [
    ./options.nix
    ./parts/behavior.nix
    ./parts/session.nix
    ./parts/samba.nix
    ./parts/networking.nix
  ] ++ filePaths ++ subIndex;
}