# domains/lib/mkSimpleApp.nix
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
