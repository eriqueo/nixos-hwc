# domains/system/apps/fabric/index.nix
#
# FAÇADE: Fabric system-level configuration
# Forwards to domain-specific modules (home, server) based on toggle flags
# Namespace: hwc.system.apps.fabric.*

{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.hwc.system.apps.fabric;
  homeMod = ../../home/apps/fabric;
  serverMod = ../../server/apps/fabric-api;
  chosenPkg =
    if cfg.package != null then cfg.package
    else (inputs.fabric.packages.${pkgs.system}.default or inputs.fabric.packages.${pkgs.system}.fabric);
in
{
  imports = [
    ./options.nix
    homeMod
    serverMod
  ];

  config = lib.mkMerge [
    # Forward to home domain when enableHome is true
    (lib.mkIf cfg.enableHome {
      hwc.home.apps.fabric = {
        enable = true;
        package = chosenPkg;
        provider = cfg.provider;
        model = cfg.model;
        env = cfg.env;
        initPatterns = cfg.initPatterns;
      };
    })

    # Forward to server domain when enableApi is true
    (lib.mkIf cfg.enableApi {
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
