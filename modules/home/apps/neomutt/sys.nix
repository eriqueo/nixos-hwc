# modules/home/apps/neomutt/sys.nix
#
# System lane wiring for neomutt.
# Charter v7: co-located sys.nix files expose System/HW/Security data
# to the Home Manager unit via its own options.

{ lib, config, ... }:

let
  cfg = config.features.neomutt;
  secMaterials = lib.attrByPath [ "hwc" "security" "materials" ] {} config;
in {
  config = lib.mkIf cfg.enable {
    features.neomutt.materials = secMaterials;
  };
}
