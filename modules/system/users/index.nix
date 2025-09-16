{ lib, ... }:
let
  dir = builtins.readDir ./.;
  files = lib.filterAttrs (n: t:
    t == "regular" && lib.hasSuffix ".nix" n && n != "index.nix" && !lib.hasSuffix ".bak.nix" n
  ) dir;
  filePaths = lib.mapAttrsToList (n: _: ./. + "/${n}") files;
in { imports = filePaths; }