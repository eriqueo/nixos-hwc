{ lib, ... }:
let
  dir = builtins.readDir ./.;
  files = lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n && n != "index.nix") dir;
  paths = lib.mapAttrsToList (n: _: ./. + "/${n}") files;
in { imports = paths; }
