{ lib, pkgs, cfg }:
let
  patch = ./patches/afew-importlib-metadata.patch;
  base = if cfg.package != null then cfg.package else pkgs.afew;
in
base.overrideAttrs (old: {
  patches = (old.patches or []) ++ [ patch ];
})
