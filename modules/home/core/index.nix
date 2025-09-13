# modules/home/core/index.nix — aggregates core home functionality
{ lib, ... }:
let
  dir = builtins.readDir ./.;

  # import only plain top-level files you intend to keep alongside subdirs
  files = lib.filterAttrs (n: t:
    t == "regular"
    && lib.hasSuffix ".nix" n
    && n != "index.nix"
    && !(lib.hasSuffix ".bak.nix" n)
  ) dir;

  filePaths = lib.mapAttrsToList (n: _: ./. + "/${n}") files;
in {
  imports = filePaths;
}