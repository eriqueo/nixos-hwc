{ lib, ... }:
let
  gatherSys = dirPath:
    let
      entries = builtins.readDir dirPath;
      subdirs  = lib.attrNames (lib.filterAttrs (_: t: t == "directory") entries);
      paths    = map (n: dirPath + "/${n}/sys.nix") subdirs;
    in lib.filter builtins.pathExists paths;
in
{
  imports =
    [ ../modules/system/index.nix ]
    ++ (gatherSys ../modules/home/apps)
    ++ (gatherSys ../modules/services)
    ++ (gatherSys ../modules/infrastructure);
}
