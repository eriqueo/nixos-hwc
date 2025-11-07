# domains/server/apps/fabric-api/index.nix
#
# IMPLEMENTATION: Fabric REST API service (systemd)
# Namespace: hwc.server.apps.fabricApi.*

{ config, pkgs, lib, inputs, ... }:
let
  cfg = config.hwc.server.apps.fabricApi;
  fabricPkg =
    if cfg.package != null then cfg.package
    else (inputs.fabric.packages.${pkgs.system}.default or inputs.fabric.packages.${pkgs.system}.fabric);
  listenArg = "--listen=${cfg.listenAddress}:${toString cfg.port}";
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    # Add Fabric to system packages
    environment.systemPackages = [ fabricPkg ];

    # Systemd service for Fabric API
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
        Environment = lib.mapAttrsToList (n: v: "${n}=${v}") cfg.extraEnv;
      } // lib.optionalAttrs (cfg.envFile != null) {
        EnvironmentFile = cfg.envFile;
      };
    };

    # Firewall configuration (only if not localhost and explicitly enabled)
    networking.firewall = lib.mkIf (cfg.openFirewall && cfg.listenAddress != "127.0.0.1") {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}
