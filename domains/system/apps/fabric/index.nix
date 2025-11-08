# domains/system/apps/fabric/index.nix
#
# Fabric system façade - Forwards configuration to appropriate domain modules
{ config, lib, ... }:
with lib;
let
  cfg = config.hwc.system.apps.fabric;
  chosenPkg = cfg.package;
in
{
  imports = [
    ./options.nix
    ../../../server/apps/fabric-api/index.nix
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
      hwc.server.apps.fabricApi = {
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
