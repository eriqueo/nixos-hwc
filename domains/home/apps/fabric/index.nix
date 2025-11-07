# domains/home/apps/fabric/index.nix
#
# IMPLEMENTATION: Fabric CLI for user environment (Home Manager)
# Namespace: hwc.home.apps.fabric.*

{ config, pkgs, lib, inputs, ... }:
let
  cfg = config.hwc.home.apps.fabric;
  fabricPkg =
    if cfg.package != null then cfg.package
    else (inputs.fabric.packages.${pkgs.system}.default or inputs.fabric.packages.${pkgs.system}.fabric);
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    # Add Fabric to user packages
    home.packages = [ fabricPkg ];

    # Set environment variables for Fabric
    home.sessionVariables = {
      FABRIC_PROVIDER = cfg.provider;
      FABRIC_MODEL = cfg.model;
    } // cfg.env;

    # Ensure config directory exists
    xdg.configFile."fabric/.keep".text = "";

    # Optional: Initialize patterns on first activation
    home.activation.fabricInit = lib.mkIf cfg.initPatterns (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -d "$HOME/.config/fabric/patterns" ]; then
          if command -v fabric >/dev/null 2>&1; then
            $DRY_RUN_CMD ${fabricPkg}/bin/fabric --setup || true
            $DRY_RUN_CMD ${fabricPkg}/bin/fabric --updatepatterns || true
          fi
        fi
      ''
    );
  };
}
