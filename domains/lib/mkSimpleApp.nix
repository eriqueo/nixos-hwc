# domains/lib/mkSimpleApp.nix
#
# HWC-EXCEPTION(Law 10): mkEnableOption outside an index.nix
# Justification: this is a module FACTORY, not a module. The option it builds
#   belongs to the caller's domains/home/apps/<name>/index.nix, which declares
#   it by calling this with its own folder name — so the declaration is still
#   at the index.nix the reader would look in, exactly as Law 10 intends.
#   Same class of exception as domains/paths/paths.nix.
# Plan: permanent by design (see CHARTER.md §4)
# Revocable: yes (if the factory is inlined back into each caller)
#
# Helper for one-package Home Manager app modules: an enable toggle that
# installs a single package. Preserves Charter shape — the caller's
# index.nix lives in domains/home/apps/<name>/ and passes its own folder
# name, keeping Law 2 (namespace = folder) visible at the call site.
#
# Usage (domains/home/apps/<name>/index.nix):
#   import ../../../lib/mkSimpleApp.nix {
#     name = "<name>";
#     description = "<mkEnableOption description>";
#     package = pkgs: pkgs.<attr>;
#   }

{ name, description, package }:

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.${name};
in
{
  options.hwc.home.apps.${name} = {
    enable = lib.mkEnableOption description;
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ (package pkgs) ];
  };
}
