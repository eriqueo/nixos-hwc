# domains/home/apps/fabric/index.nix
#
# Fabric CLI for user environment - Home Manager implementation
{ config, lib, pkgs, inputs, ... }:
with lib;
let
  cfg = config.hwc.home.apps.fabric-bak;
  fabricPkg = if cfg.package != null then cfg.package else inputs.fabric.packages.${pkgs.system}.default;
in
{
  imports = [ ./options.nix ];

  config = mkIf cfg.enable {
    home.packages = [ fabricPkg ];

    home.sessionVariables = {
      FABRIC_PROVIDER = cfg.provider;
      FABRIC_MODEL = cfg.model;
    } // cfg.env;

    # Create config directory
    xdg.configFile."fabric/.keep".text = "";

    # Optional: Initialize patterns on first activation
    home.activation.fabricInit = mkIf cfg.initPatterns (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -d "$HOME/.config/fabric/patterns" ]; then
          $DRY_RUN_CMD ${fabricPkg}/bin/fabric --setup || true
          $DRY_RUN_CMD ${fabricPkg}/bin/fabric --updatepatterns || true
        fi
      ''
    );
  };
}
