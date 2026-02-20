{ lib, config, pkgs, ... }:
let
  helpers = import ../../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.server.containers.paperless;

  envDir = "/run/paperless-env";
  envFile = "${envDir}/paperless.env";

  ocrLanguages = lib.concatStringsSep "+" cfg.ocr.languages;
  paperlessUrlBase = "https://${config.hwc.server.reverseProxy.domain}";

  generateEnvScript = pkgs.writeShellScript "generate-paperless-env" ''
    set -euo pipefail

    install -d -m 0750 -o root -g secrets ${envDir}

    SECRET_KEY=$(cat ${config.age.secrets.paperless-secret-key.path})
    ADMIN_PASSWORD=$(cat ${config.age.secrets.paperless-admin-password.path})

    cat > ${envFile} <<EOF
    PAPERLESS_SECRET_KEY=$SECRET_KEY
    PAPERLESS_ADMIN_USER=${cfg.admin.user}
    PAPERLESS_ADMIN_PASSWORD=$ADMIN_PASSWORD
    PAPERLESS_ADMIN_EMAIL=${cfg.admin.email}

    PAPERLESS_URL=${paperlessUrlBase}
    PAPERLESS_FORCE_SCRIPT_NAME=${cfg.reverseProxy.path}
    PAPERLESS_CORS_ALLOWED_ORIGINS=${paperlessUrlBase}
    PAPERLESS_CSRF_TRUSTED_ORIGINS=${paperlessUrlBase}

    PAPERLESS_TIME_ZONE=${config.time.timeZone or "UTC"}

    PAPERLESS_OCR_LANGUAGE=${ocrLanguages}
    PAPERLESS_OCR_OUTPUT_TYPE=${cfg.ocr.outputType}

    PAPERLESS_CONSUMER_POLLING=${toString cfg.consumer.polling}
    PAPERLESS_CONSUMER_DELETE_ORIGINALS=${if cfg.consumer.deleteOriginals then "true" else "false"}

    PAPERLESS_DBHOST=${cfg.database.host}
    PAPERLESS_DBPORT=${toString cfg.database.port}
    PAPERLESS_DBNAME=${cfg.database.name}
    PAPERLESS_DBUSER=${cfg.database.user}

    PAPERLESS_REDIS=redis://${cfg.redis.host}:${toString cfg.redis.port}
    EOF

    chown root:secrets ${envFile}
    chmod 0640 ${envFile}
  '';

  cleanupScript = pkgs.writeShellScript "paperless-cleanup" ''
    set -euo pipefail

    ${lib.optionalString (cfg.storage.stagingDir != null) ''
      ${pkgs.findutils}/bin/find ${cfg.storage.stagingDir} -type f -mtime +${toString cfg.retention.cleanup.stagingDays} -delete 2>/dev/null || true
    ''}

    ${lib.optionalString (cfg.storage.exportDir != null) ''
      ${pkgs.findutils}/bin/find ${cfg.storage.exportDir} -type f -mtime +${toString cfg.retention.cleanup.exportDays} -delete 2>/dev/null || true
    ''}

    ${lib.optionalString (cleanupDirs != []) ''
      ${pkgs.findutils}/bin/find ${cleanupDirsStr} -type d -empty -delete 2>/dev/null || true
    ''}
  '';

  paperlessVolumes = lib.flatten [
    (lib.optional (cfg.storage.dataDir != null) "${cfg.storage.dataDir}:/usr/src/paperless/data:rw")
    (lib.optional (cfg.storage.mediaDir != null) "${cfg.storage.mediaDir}:/usr/src/paperless/media:rw")
    (lib.optional (cfg.storage.consumeDir != null) "${cfg.storage.consumeDir}:/usr/src/paperless/consume:rw")
    (lib.optional (cfg.storage.exportDir != null) "${cfg.storage.exportDir}:/usr/src/paperless/export:rw")
  ];

  cleanupDirs = lib.filter (dir: dir != null) [ cfg.storage.stagingDir cfg.storage.exportDir ];
  cleanupDirsStr = lib.concatStringsSep " " cleanupDirs;

in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "paperless";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = false;
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:${toString cfg.port}:8000" ];
      volumes = paperlessVolumes;
      environmentFiles = [ envFile ];
      memory = cfg.resources.memory;
      cpus = cfg.resources.cpus;
    })

    {
      # Generate environment file from secrets before container starts
      systemd.services.paperless-env = {
        description = "Generate Paperless-NGX environment file";
        wantedBy = [ "podman-paperless.service" ];
        requiredBy = [ "podman-paperless.service" ];
        before = [ "podman-paperless.service" ];
        after = [ "agenix.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${generateEnvScript}";
        };
      };

      # Ensure container waits for env file
      systemd.services."podman-paperless" = {
        after = [ "network-online.target" "postgresql.service" "paperless-env.service" ]
          ++ lib.optional (cfg.network.mode == "media") "init-media-network.service";
        requires = [ "paperless-env.service" ];
        wants = [ "network-online.target" ];
      };

      # Register database with PostgreSQL service
      hwc.server.databases.postgresql.databases = [
        cfg.database.name
      ];

      # Ensure database privileges for Paperless user
      systemd.services.postgresql.postStart = lib.mkAfter ''
        $PSQL -d ${cfg.database.name} -c "GRANT ALL PRIVILEGES ON DATABASE ${cfg.database.name} TO ${cfg.database.user};" || true
        $PSQL -d ${cfg.database.name} -c "GRANT USAGE, CREATE ON SCHEMA public TO ${cfg.database.user};" || true
        $PSQL -d ${cfg.database.name} -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${cfg.database.user};" || true
        $PSQL -d ${cfg.database.name} -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${cfg.database.user};" || true
        $PSQL -d ${cfg.database.name} -c "GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ${cfg.database.user};" || true
        $PSQL -d ${cfg.database.name} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${cfg.database.user};" || true
        $PSQL -d ${cfg.database.name} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${cfg.database.user};" || true
        $PSQL -d ${cfg.database.name} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${cfg.database.user};" || true
      '';

      # Cleanup timer for auto-managed staging/export
      systemd.services.paperless-cleanup = lib.mkIf cfg.retention.cleanup.enable {
        description = "Paperless-NGX staging/export cleanup";
        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
        script = "${cleanupScript}";
      };

      systemd.timers.paperless-cleanup = lib.mkIf cfg.retention.cleanup.enable {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.retention.cleanup.schedule;
          Persistent = true;
        };
      };

      # VALIDATION
      assertions = [
        {
          assertion = !cfg.enable || config.hwc.server.databases.postgresql.enable;
          message = "paperless requires PostgreSQL (hwc.server.databases.postgresql.enable = true)";
        }
        {
          assertion = !cfg.enable || config.hwc.server.databases.redis.enable;
          message = "paperless requires Redis (hwc.server.databases.redis.enable = true)";
        }
        {
          assertion = !cfg.enable || (config.age.secrets ? paperless-secret-key);
          message = "paperless requires paperless-secret-key secret to be declared";
        }
        {
          assertion = !cfg.enable || (config.age.secrets ? paperless-admin-password);
          message = "paperless requires paperless-admin-password secret to be declared";
        }
        {
          assertion = !cfg.enable || cfg.storage.consumeDir != null;
          message = "paperless requires storage.consumeDir to be set";
        }
        {
          assertion = !cfg.enable || cfg.storage.exportDir != null;
          message = "paperless requires storage.exportDir to be set";
        }
        {
          assertion = !cfg.enable || cfg.storage.stagingDir != null;
          message = "paperless requires storage.stagingDir to be set";
        }
        {
          assertion = !cfg.enable || cfg.storage.mediaDir != null;
          message = "paperless requires storage.mediaDir to be set";
        }
        {
          assertion = !cfg.enable || cfg.storage.dataDir != null;
          message = "paperless requires storage.dataDir to be set";
        }
        {
          assertion = cfg.ocr.languages != [];
          message = "paperless OCR languages list must not be empty";
        }
      ];
    }
  ]);
}
