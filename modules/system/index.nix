# modules/system/index.nix
{ lib, ... }:
let
  dir = builtins.readDir ./.;

  # only import known subtrees in a stable order
  wantedDirs = [ "core" "packages" "services" "storage" ];
  subIndex =
    lib.pipe wantedDirs [
      (ns: lib.filter (n: lib.hasAttr n dir && dir.${n} == "directory") ns)
      (ns: map (n: ./. + "/${n}/index.nix") ns)
    ];

  # import only plain top-level files you intend to keep alongside those dirs
  files = lib.filterAttrs (n: t:
    t == "regular"
    && lib.hasSuffix ".nix" n
    && n != "index.nix"
    && !(lib.hasSuffix ".bak.nix" n)
  ) dir;

  filePaths = lib.mapAttrsToList (n: _: ./. + "/${n}") files;
in {
  imports = filePaths ++ subIndex;
}
