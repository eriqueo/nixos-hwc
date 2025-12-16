# domains/system/apps/fabric/index.nix
#
# Fabric system façade - Forwards configuration to appropriate domain modules
#
# STATUS: DISABLED - Waiting for upstream fix
# ISSUE: github:danielmiessler/fabric uses gomod2nix with darwin.apple_sdk_11_0
#        which was removed from nixpkgs. Causes build failures even on Linux.
# TODO: Re-enable when either:
#       1. Upstream fixes gomod2nix Darwin SDK dependency
#       2. We add an overlay to patch/override the Fabric package
# TRACKED: See flake.nix line 48 for fabric input (currently commented)
#
{ config, lib, ... }:
with lib;
let
  cfg = config.hwc.system.apps.fabric;
  chosenPkg = cfg.package;
in
{
  imports = [
    ./options.nix
    ../../../server/fabric-api/index.nix
  ];

  config = mkMerge [
    # Forward to Home Manager via home-manager.users when enableHome is true
    (mkIf cfg.enableHome {
      home-manager.users.eric = {
        hwc.home.apps.fabric = {
          enable = true;
          package = chosenPkg;
          provider = cfg.provider;
          model = cfg.model;
          env = cfg.env;
          initPatterns = cfg.initPatterns;
        };
      };
    })

    # Forward to systemd service module when enableApi is true
    (mkIf cfg.enableApi {
      hwc.server.fabricApi = {
        enable = true;
        package = chosenPkg;
        listenAddress = cfg.api.listenAddress;
        port = cfg.api.port;
        envFile = cfg.api.envFile;
        extraEnv = cfg.api.extraEnv;
        openFirewall = cfg.api.openFirewall;
      };
    })
  ];
}
