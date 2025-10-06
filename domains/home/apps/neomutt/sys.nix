# modules/home/apps/neomutt/sys.nix
#
# System lane wiring for neomutt.
# Charter v7: co-located sys.nix files expose System/HW/Security data
# to the Home Manager unit via its own options.

{ lib, config, pkgs, ... }:

let
  
  cfg = config.hwc.home.apps.neomutt;
  secMaterials = lib.attrByPath [ "hwc" "security" "materials" ] {} config;
in {
  imports = [ ./options.nix ];
  config = lib.mkIf cfg.enable {
    features.neomutt.materials = secMaterials;
  };
}
