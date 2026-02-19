{ lib, config, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
  paths = config.hwc.paths;
in
{
  options.hwc.server.containers.paperless = {
    enable = mkEnableOption "Paperless-NGX document management (containerized)";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/paperless-ngx/paperless-ngx:2.14";
      description = "Paperless-NGX container image";
    };

    port = mkOption {
      type = types.port;
      default = 8000;
      description = "Internal HTTP port for Paperless";
    };

    network.mode = mkOption {
      type = types.enum [ "media" "host" ];
      default = "media";
      description = "Network mode for the container";
    };

    database = {
      host = mkOption {
        type = types.str;
        default = "10.89.0.1";  # media-network gateway
        description = "PostgreSQL host (containers can't use localhost)";
      };

      port = mkOption {
        type = types.port;
        default = 5432;
        description = "PostgreSQL port";
      };

      name = mkOption {
        type = types.str;
        default = "paperless";
        description = "PostgreSQL database name";
      };

      user = mkOption {
        type = types.str;
        default = "eric";
        description = "PostgreSQL user";
      };
    };

    redis = {
      host = mkOption {
        type = types.str;
        default = "10.89.0.1";  # media-network gateway
        description = "Redis host";
      };

      port = mkOption {
        type = types.port;
        default = 6379;
        description = "Redis port";
      };
    };

    storage = {
      consumeDir = mkOption {
        type = types.nullOr types.path;
        default = if paths.hot.root != null then "${paths.hot.root}/documents/consume" else null;
        description = "Consume directory (drop zone for auto-import)";
      };

      exportDir = mkOption {
        type = types.nullOr types.path;
        default = if paths.hot.root != null then "${paths.hot.root}/documents/export" else null;
        description = "Export directory";
      };

      stagingDir = mkOption {
        type = types.nullOr types.path;
        default = if paths.hot.root != null then "${paths.hot.root}/documents/staging" else null;
        description = "Staging directory for pre-processing";
      };

      mediaDir = mkOption {
        type = types.nullOr types.path;
        default = if paths.media.root != null then "${paths.media.root}/documents/paperless" else null;
        description = "Archive storage (originals, archive, thumbnails)";
      };

      dataDir = mkOption {
        type = types.nullOr types.path;
        default = if paths.apps.root != null then "${paths.apps.root}/paperless/data" else null;
        description = "Paperless data directory (index, db cache)";
      };
    };

    ocr = {
      languages = mkOption {
        type = types.listOf types.str;
        default = [ "eng" ];
        description = "Tesseract OCR language codes";
      };

      outputType = mkOption {
        type = types.enum [ "pdf" "pdfa" "pdfa-2" ];
        default = "pdfa";
        description = "OCR output format (pdf, pdfa, pdfa-2)";
      };
    };

    consumer = {
      polling = mkOption {
        type = types.int;
        default = 60;
        description = "Seconds between consume folder scans";
      };

      deleteOriginals = mkOption {
        type = types.bool;
        default = false;
        description = "Delete originals after successful import";
      };
    };

    admin = {
      user = mkOption {
        type = types.str;
        default = "eric";
        description = "Initial admin username";
      };

      email = mkOption {
        type = types.str;
        default = "eric@hwc.local";
        description = "Initial admin email";
      };
    };

    reverseProxy = {
      path = mkOption {
        type = types.str;
        default = "/docs";
        description = "Reverse proxy subpath";
      };
    };

    resources = {
      memory = mkOption {
        type = types.str;
        default = "4g";
        description = "Memory limit for Paperless container";
      };

      cpus = mkOption {
        type = types.str;
        default = "2.0";
        description = "CPU limit for Paperless container";
      };
    };

    retention = {
      cleanup = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Paperless staging/export cleanup timer";
        };

        schedule = mkOption {
          type = types.str;
          default = "daily";
          description = "systemd OnCalendar schedule for cleanup";
        };

        stagingDays = mkOption {
          type = types.int;
          default = 7;
          description = "Delete staging files older than N days";
        };

        exportDays = mkOption {
          type = types.int;
          default = 30;
          description = "Delete export files older than N days";
        };
      };
    };
  };
}
