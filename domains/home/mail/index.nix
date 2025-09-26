# domains/home/mail/index.nix
{ lib, ... }:
let
  dir = builtins.readDir ./.;

  # only take subdirectories that have an index.nix
  mailDirs =
    lib.filter (n: let d = dir.${n}; in d == "directory" && builtins.pathExists (./. + "/${n}/index.nix"))
      (lib.attrNames dir);

  # optionally filter out scratch dirs, backups, etc.
  mailDirsWanted = lib.filter (n: !(lib.hasSuffix "-bak" n)) mailDirs;

  imports = map (n: ./. + "/${n}/index.nix") (lib.sort (a: b: a < b) mailDirsWanted);
in {
  inherit imports;
}
