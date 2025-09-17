{ lib, ... }:
let
  gatherSys = dirPath:
    let
      entries = builtins.readDir dirPath;
      subdirs  = lib.attrNames (lib.filterAttrs (_: t: t == "directory") entries);
      paths    = map (n: dirPath + "/${n}/sys.nix") subdirs;
    in lib.filter builtins.pathExists paths;
  
  # Gather server sys.nix files but exclude containers directory
  gatherServerSys = dirPath:
    let
      entries = builtins.readDir dirPath;
      subdirs = lib.attrNames (lib.filterAttrs (n: t: t == "directory" && n != "containers") entries);
      paths = map (n: dirPath + "/${n}/sys.nix") subdirs;
    in lib.filter builtins.pathExists paths;
in
{
  imports =
    [ ../modules/system/index.nix ]
    ++ (gatherSys ../modules/home/apps)
    ++ (gatherServerSys ../modules/server)
    ++ (gatherSys ../modules/infrastructure);
}
