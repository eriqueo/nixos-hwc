# domains/server/apps/fabric-api/index.nix
#
# Fabric REST API service - systemd implementation
{ config, lib, pkgs, inputs, ... }:
with lib;
let
  cfg = config.hwc.server.apps.fabricApi;
  fabricPkg = if cfg.package != null then cfg.package else inputs.fabric.packages.${pkgs.system}.default;
  listenArg = "${cfg.listenAddress}:${toString cfg.port}";
in
{
  imports = [ ./options.nix ];

  config = mkIf cfg.enable {
    systemd.services.fabric-api = {
      description = "Fabric REST API";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = "${fabricPkg}/bin/fabric --serve ${listenArg}";
        Restart = "on-failure";
        RestartSec = "10s";

        # Security hardening
        DynamicUser = true;
        StateDirectory = "fabric-api";

        # Environment variables
        Environment = mapAttrsToList (n: v: "${n}=${v}") cfg.extraEnv;
      } // optionalAttrs (cfg.envFile != null) {
        EnvironmentFile = cfg.envFile;
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}
