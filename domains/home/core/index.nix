{ lib, ... }:
let
  dir = builtins.readDir ./.;

  # import all child dirs under core (mail included) if they expose index.nix
  subIndex =
    lib.pipe (lib.attrNames (lib.filterAttrs (_: t: t == "directory") dir)) [
      (ns: map (n: ./. + "/${n}/index.nix") ns)
      (paths: lib.filter builtins.pathExists paths)
    ];

  # import any plain .nix files sitting directly in core/
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
