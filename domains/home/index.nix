# domains/home/index.nix
{ lib, osConfig ? {}, ... }:
let
  dir = builtins.readDir ./.;

  # add "mail" here
  wantedDirs = [ "core" "environment" "theme" "apps" "mail" ];

  subIndex =
    lib.pipe wantedDirs [
      (ns: lib.filter (n: lib.hasAttr n dir && dir.${n} == "directory") ns)
      (ns: map (n: ./. + "/${n}/index.nix") ns)
    ];

  files = lib.filterAttrs (n: t:
    t == "regular"
    && lib.hasSuffix ".nix" n
    && n != "index.nix"
    && !(lib.hasSuffix ".bak.nix" n)
  ) dir;

  filePaths = lib.mapAttrsToList (n: _: ./. + "/${n}") files;
in {
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = filePaths ++ subIndex;

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};

}
