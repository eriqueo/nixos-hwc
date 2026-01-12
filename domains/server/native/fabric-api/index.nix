# domains/server/fabric-api/index.nix
#
# Fabric REST API service - systemd implementation
{ config, lib, pkgs, inputs, ... }:
with lib;
let
  cfg = config.hwc.server.native.fabric-api;
  system = pkgs.stdenv.hostPlatform.system;
  fabricPkg = if cfg.package != null then cfg.package else inputs.fabric.packages.${system}.default;
  listenArg = "${cfg.listenAddress}:${toString cfg.port}";
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
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
        User = lib.mkForce "eric";
        Group = lib.mkForce "users";
        # Environment variables
        Environment = mapAttrsToList (n: v: "${n}=${v}") cfg.extraEnv;
      } // optionalAttrs (cfg.envFile != null) {
        EnvironmentFile = cfg.envFile;
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };
    assertions = [];
  };

}
