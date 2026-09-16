{ lib, config, pkgs, ... }:
let
  helpers = import ../../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.business.paperless;

  envDir = "/run/paperless-env";
  envFile = "${envDir}/paperless.env";

  ocrLanguages = lib.concatStringsSep "+" cfg.ocr.languages;

  # Sidecar container names. These are also the DNS names paperless dials, so
  # the name and the endpoint below derive from one binding rather than two
  # string literals that can drift apart.
  tikaName = "paperless-tika";
  gotenbergName = "paperless-gotenberg";
  tikaPort = 9998;
  gotenbergPort = 3000;

  # Paperless' own origin. This is NOT cosmetic: Django validates the Origin of
  # every unsafe request against PAPERLESS_CSRF_TRUSTED_ORIGINS below, so if
  # this drifts from the host Caddy actually serves paperless under, GETs keep
  # returning 200 and every login/upload POST fails "CSRF verification failed".
  # A status-code smoke test cannot see that — it has to be an authenticated POST.
  paperlessUrlBase = "https://paperless.${config.hwc.networking.shared.vhostDomain}";

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
    ${lib.optionalString (cfg.reverseProxy.path != "") ''
    PAPERLESS_FORCE_SCRIPT_NAME=${cfg.reverseProxy.path}''}
    PAPERLESS_CORS_ALLOWED_ORIGINS=${paperlessUrlBase}
    PAPERLESS_CSRF_TRUSTED_ORIGINS=${paperlessUrlBase}

    PAPERLESS_TIME_ZONE=${config.time.timeZone or "UTC"}

    PAPERLESS_OCR_LANGUAGE=${ocrLanguages}
    PAPERLESS_OCR_OUTPUT_TYPE=${cfg.ocr.outputType}

    PAPERLESS_CONSUMER_POLLING=${toString cfg.consumer.polling}
    PAPERLESS_CONSUMER_DELETE_ORIGINALS=${if cfg.consumer.deleteOriginals then "true" else "false"}
    PAPERLESS_CONSUMER_RECURSIVE=${lib.boolToString cfg.consumer.recursive}
    PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS=${lib.boolToString cfg.consumer.subdirsAsTags}

    PAPERLESS_DBHOST=${cfg.database.host}
    PAPERLESS_DBPORT=${toString cfg.database.port}
    PAPERLESS_DBNAME=${cfg.database.name}
    PAPERLESS_DBUSER=${cfg.database.user}

    PAPERLESS_REDIS=redis://${cfg.redis.host}:${toString cfg.redis.port}
    ${lib.optionalString cfg.officeIngest.enable ''
    PAPERLESS_TIKA_ENABLED=1
    PAPERLESS_TIKA_ENDPOINT=http://${tikaName}:${toString tikaPort}
    PAPERLESS_TIKA_GOTENBERG_ENDPOINT=http://${gotenbergName}:${toString gotenbergPort}''}
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
      # -mindepth 1 keeps the prune INSIDE each dir. Without it find's start
      # point is itself a match, so staging/ and export/ — normally empty —
      # deleted themselves every night. They are podman bind-mount sources, so
      # the next container start died with
      #   Error: statfs /mnt/hot/documents/export: no such file or directory
      # (2026-07-06 crash loop, again 2026-08-20). Same shape already burned
      # media-cleanup via slskd; see domains/data/storage/parts/cleanup.nix:17.
      ${pkgs.findutils}/bin/find ${cleanupDirsStr} -mindepth 1 -type d -empty -delete 2>/dev/null || true
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

    # Office-ingest sidecars. They live here beside the paperless container
    # rather than in a parts/tika.nix of their own: they have no independent
    # lifecycle, no consumer other than paperless, and their endpoints are the
    # same env file generated twenty lines up. A separate file would put the
    # two halves of one binding in two places (Charter §0.13).
    (lib.mkIf cfg.officeIngest.enable (lib.mkMerge [
      (helpers.mkContainer {
        name = tikaName;
        image = cfg.officeIngest.tikaImage;
        networkMode = cfg.network.mode;
        gpuEnable = false;
        timeZone = config.time.timeZone or "UTC";
        ports = [];   # media-network DNS only; nothing to claim in routes.nix
        memory = "2g";
        cpus = "2.0";
      })

      (helpers.mkContainer {
        name = gotenbergName;
        image = cfg.officeIngest.gotenbergImage;
        networkMode = cfg.network.mode;
        gpuEnable = false;
        timeZone = config.time.timeZone or "UTC";
        ports = [];
        memory = "2g";
        cpus = "2.0";
        # Gotenberg's chromium route renders .eml. Left at its defaults it will
        # fetch remote content — tracking pixels and scripts out of untrusted
        # mail — so JavaScript is off and the allow-list is restricted to the
        # temp file Gotenberg was handed. Upstream paperless-ngx ships the same
        # two flags for the same reason.
        cmd = [
          "gotenberg"
          "--chromium-disable-javascript=true"
          "--chromium-allow-list=file:///tmp/.*"
        ];
      })
    ]))

    {
      # Storage dirs (incl. the bind-mount sources) are declared once, in
      # parts/directories.nix. A second producer for the same four paths used
      # to live here; systemd-tmpfiles kept the first line and logged
      # "Duplicate line for path ..., ignoring", so its 0775 never applied and
      # the block only looked like it was doing something.

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
        # Ordering only for the sidecars, deliberately not `requires`. Paperless
        # dials Tika/Gotenberg per consumed document, not at startup, so a
        # sidecar that is slow or down must degrade to "Office files don't
        # import" — not take the whole document store offline. Coupling the
        # lifecycles is how this module got a 1600-restart crash loop before.
        after = [ "network-online.target" "postgresql.service" "paperless-env.service" ]
          ++ lib.optional (cfg.network.mode == "media") "init-media-network.service"
          ++ lib.optionals cfg.officeIngest.enable [
            "podman-${tikaName}.service"
            "podman-${gotenbergName}.service"
          ];
        requires = [ "paperless-env.service" ];
        wants = [ "network-online.target" ];
      };

      # Register database with PostgreSQL service
      hwc.data.databases.postgresql.databases = [
        cfg.database.name
      ];

      # No postStart privilege block. Eight `$PSQL` GRANT/ALTER DEFAULT PRIVILEGES
      # lines used to sit here and none of them ever ran: `$PSQL` is undefined in
      # the generated postgresql post-start script and `|| true` swallowed the
      # command-not-found (audit 2026-08-28, domains/data/databases/README.md).
      #
      # They are not restored, because they were never load-bearing. Paperless
      # connects as `${cfg.database.user}`, which is `eric` — a Postgres superuser
      # who also owns all 68 tables in this database. A grant to the owner grants
      # nothing. `pg_class.relacl` in `paperless` holds zero rows, which is the
      # measurement that proves no grant here has ever taken effect.

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
          assertion = !cfg.enable || config.hwc.data.databases.postgresql.enable;
          message = "paperless requires PostgreSQL (hwc.data.databases.postgresql.enable = true)";
        }
        {
          assertion = !cfg.enable || config.hwc.data.databases.redis.enable;
          message = "paperless requires Redis (hwc.data.databases.redis.enable = true)";
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
        {
          # The sidecars are addressed by podman DNS name. In host mode there is
          # no such DNS, and paperless would silently fall back to skipping every
          # Office file — the exact failure officeIngest exists to remove.
          assertion = !cfg.officeIngest.enable || cfg.network.mode == "media";
          message = "paperless officeIngest requires network.mode = \"media\" (Tika/Gotenberg are resolved by container DNS)";
        }
        {
          assertion = !cfg.consumer.subdirsAsTags || cfg.consumer.recursive;
          message = "paperless consumer.subdirsAsTags requires consumer.recursive (subdirectories are never scanned otherwise)";
        }
      ];
    }
  ]);
}
