# domains/system/core/authentik/parts/config.nix
{ lib, config, pkgs, ... }:

let
  helpers = import ../../../../lib/mkContainer.nix { inherit lib pkgs; };
  inherit (helpers) mkContainer;
  cfg = config.hwc.system.core.authentik;
  paths = config.hwc.paths;
  authentikRoot = "${paths.state}/authentik";
  authentikMedia = "${authentikRoot}/media";
  authentikTemplates = "${authentikRoot}/templates";
  envDir = "/run/authentik-env";
  envFile = "${envDir}/authentik.env";
  generateEnvScript = pkgs.writeShellScript "generate-authentik-env" ''
    set -euo pipefail
    install -d -m 0750 -o root -g secrets ${envDir}
    SECRET_KEY=$(cat ${config.age.secrets.authentik-secret-key.path})
    DB_PASSWORD=$(cat ${config.age.secrets.authentik-db-password.path})
    cat > ${envFile} <<EOF
    AUTHENTIK_SECRET_KEY=$SECRET_KEY
    AUTHENTIK_POSTGRESQL__PASSWORD=$DB_PASSWORD
    EOF
    chown root:secrets ${envFile}
    chmod 0640 ${envFile}
  '';
  sharedEnvironment = {
    PUID = "1000";
    PGID = "100";
    TZ = config.time.timeZone or "America/Denver";
    AUTHENTIK_POSTGRESQL__HOST = cfg.database.host;
    AUTHENTIK_POSTGRESQL__PORT = toString cfg.database.port;
    AUTHENTIK_POSTGRESQL__USER = cfg.database.user;
    AUTHENTIK_POSTGRESQL__NAME = cfg.database.name;
    AUTHENTIK_REDIS__HOST = cfg.redis.host;
    AUTHENTIK_REDIS__PORT = toString cfg.redis.port;
    AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS = ''["127.0.0.0/8","10.0.0.0/8","172.16.0.0/12","192.168.0.0/16","100.64.0.0/10"]'';
  };
  sharedVolumes = [
    "${authentikMedia}:/media:rw"
    "${authentikTemplates}:/templates:rw"
  ];
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    { systemd.tmpfiles.rules = [
        "d ${authentikRoot} 0755 eric users -"
        "d ${authentikMedia} 0755 eric users -"
        "d ${authentikTemplates} 0755 eric users -"
      ];
    }
    (mkContainer {
      name = "authentik-server"; image = cfg.image;
      networkMode = cfg.network.mode; gpuEnable = false;
      timeZone = config.time.timeZone or "America/Denver";
      memory = "2g"; cpus = "2.0"; memorySwap = "4g";
      environmentFiles = [ envFile ]; cmd = [ "server" ];
      extraOptions = lib.optionals (cfg.network.mode != "host") [ "--network-alias=authentik-server" ];
      ports = lib.optionals (cfg.network.mode != "host") [
        "127.0.0.1:${toString cfg.reverseProxy.internalPort}:9000"
        "127.0.0.1:${toString cfg.reverseProxy.internalHttpsPort}:9443"
      ];
      environment = sharedEnvironment; volumes = sharedVolumes;
    })
    (mkContainer {
      name = "authentik-worker"; image = cfg.image;
      networkMode = cfg.network.mode; gpuEnable = false;
      timeZone = config.time.timeZone or "America/Denver";
      memory = "2g"; cpus = "2.0"; memorySwap = "4g";
      environmentFiles = [ envFile ]; cmd = [ "worker" ];
      extraOptions = lib.optionals (cfg.network.mode != "host") [ "--network-alias=authentik-worker" ];
      ports = [];
      environment = sharedEnvironment; volumes = sharedVolumes;
      dependsOn = [ "authentik-server" ];
    })
    {
      systemd.services.authentik-env = {
        description = "Generate Authentik environment file";
        wantedBy = [ "podman-authentik-server.service" ];
        requiredBy = [ "podman-authentik-server.service" ];
        before = [ "podman-authentik-server.service" ];
        after = [ "agenix.service" ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; ExecStart = "${generateEnvScript}"; };
      };
      systemd.services."podman-authentik-server" = {
        after = [ "network-online.target" "postgresql.service" "authentik-env.service" ]
          ++ lib.optional (cfg.network.mode == "media") "init-media-network.service";
        requires = [ "authentik-env.service" ]; wants = [ "network-online.target" ];
      };
      systemd.services."podman-authentik-worker" = {
        after = [ "network-online.target" "postgresql.service" "podman-authentik-server.service" "authentik-env.service" ]
          ++ lib.optional (cfg.network.mode == "media") "init-media-network.service";
        requires = [ "authentik-env.service" ]; wants = [ "network-online.target" ];
      };
    }
    {
      services.caddy.extraConfig = lib.mkAfter ''
        ${config.hwc.networking.reverseProxy.domain}:${toString cfg.reverseProxy.port} {
          tls {
            get_certificate tailscale
            protocols tls1.2 tls1.3
          }
          reverse_proxy http://127.0.0.1:${toString cfg.reverseProxy.internalPort} {
            header_up X-Forwarded-Proto {scheme}
            header_up X-Forwarded-For {http.request.header.X-Forwarded-For}
            header_up X-Forwarded-Host {host}
            header_up X-Forwarded-Port ${toString cfg.reverseProxy.port}
            header_up Connection {http.request.header.Connection}
            header_up Upgrade {http.request.header.Upgrade}
            flush_interval -1
          }
        }
      '';
    }
    {
      networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.reverseProxy.internalPort ];
    }
    {
      hwc.data.databases.postgresql.databases = [ cfg.database.name ];
      systemd.services.postgresql.postStart = lib.mkAfter ''
        $PSQL -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${cfg.database.user}') THEN CREATE ROLE ${cfg.database.user} WITH LOGIN PASSWORD 'placeholder'; END IF; END \$\$;" || true
        $PSQL -d ${cfg.database.name} -c "GRANT ALL PRIVILEGES ON DATABASE ${cfg.database.name} TO ${cfg.database.user};" || true
        $PSQL -d ${cfg.database.name} -c "GRANT USAGE, CREATE ON SCHEMA public TO ${cfg.database.user};" || true
        $PSQL -d ${cfg.database.name} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${cfg.database.user};" || true
        $PSQL -d ${cfg.database.name} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${cfg.database.user};" || true
      '';
    }
    {
      assertions = [
        { assertion = config.hwc.data.databases.postgresql.enable; message = "Authentik requires PostgreSQL"; }
        { assertion = config.age.secrets ? authentik-secret-key; message = "Authentik requires authentik-secret-key secret"; }
        { assertion = config.age.secrets ? authentik-db-password; message = "Authentik requires authentik-db-password secret"; }
      ];
    }
  ]);
}
