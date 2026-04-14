# domains/secrets/vaultwarden/index.nix
#
# Vaultwarden - Self-hosted Bitwarden compatible password manager
# NAMESPACE: hwc.secrets.vaultwarden.*

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.secrets.vaultwarden;
  paths = config.hwc.paths;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  dataDir = "${paths.state}/vaultwarden/data";
  envDir = "/run/vaultwarden-env";
  envFile = "${envDir}/vaultwarden.env";
  generateEnvScript = pkgs.writeShellScript "generate-vaultwarden-env" ''
    set -euo pipefail
    install -d -m 0750 -o root -g secrets ${envDir}
    ADMIN_TOKEN=$(cat ${config.age.secrets.vaultwarden-admin-token.path})
    cat > ${envFile} <<EOF
    ADMIN_TOKEN=$ADMIN_TOKEN
    EOF
    chown root:secrets ${envFile}
    chmod 0640 ${envFile}
  '';
in
{
  options.hwc.secrets.vaultwarden = {
    enable = lib.mkEnableOption "Vaultwarden self-hosted password manager";
    image = lib.mkOption { type = lib.types.str; default = "docker.io/vaultwarden/server:latest"; };
    port = lib.mkOption { type = lib.types.port; default = 8222; };
    reverseProxy.port = lib.mkOption { type = lib.types.port; default = 15443; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "host" ]; default = "media"; };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "vaultwarden";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = false;
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:${toString cfg.port}:80" ];
      volumes = [ "${dataDir}:/data:rw" ];
      environment = {
        DOMAIN = "https://hwc.ocelot-wahoo.ts.net:${toString cfg.reverseProxy.port}";
        SIGNUPS_ALLOWED = "true";
        INVITATIONS_ALLOWED = "true";
        SHOW_PASSWORD_HINT = "false";
        ROCKET_PORT = "80";
      };
      environmentFiles = [ envFile ];
      memory = "512m"; cpus = "0.5"; memorySwap = "1g";
    })
    {
      systemd.tmpfiles.rules = [ "d ${dataDir} 0755 eric users -" ];
    }
    {
      systemd.services.vaultwarden-env = {
        description = "Generate Vaultwarden environment file";
        wantedBy = [ "podman-vaultwarden.service" ];
        requiredBy = [ "podman-vaultwarden.service" ];
        before = [ "podman-vaultwarden.service" ];
        after = [ "agenix.service" ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; ExecStart = "${generateEnvScript}"; };
      };
      systemd.services."podman-vaultwarden" = {
        after = [ "network-online.target" "vaultwarden-env.service" ]
          ++ lib.optional (cfg.network.mode == "media") "init-media-network.service";
        requires = [ "vaultwarden-env.service" ];
        wants = [ "network-online.target" ];
      };
    }
    {
      assertions = [{
        assertion = config.age.secrets ? vaultwarden-admin-token;
        message = "hwc.secrets.vaultwarden requires vaultwarden-admin-token secret";
      }];
    }
  ]);
}
