{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.business.paperless;
  paths = config.hwc.paths;
in
{
  # OPTIONS
  options.hwc.business.paperless = {
    enable = lib.mkEnableOption "Paperless-NGX document management (containerized)";

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/paperless-ngx/paperless-ngx:2.14";
      description = "Paperless-NGX container image";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8102;
      description = "Internal HTTP port for Paperless";
    };

    network.mode = lib.mkOption {
      type = lib.types.enum [ "media" "host" ];
      default = "media";
      description = "Network mode for the container";
    };

    database = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "10.89.0.1";  # media-network gateway
        description = "PostgreSQL host (containers can't use localhost)";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5432;
        description = "PostgreSQL port";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "paperless";
        description = "PostgreSQL database name";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "eric";
        description = "PostgreSQL user";
      };
    };

    redis = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "10.89.0.1";  # media-network gateway
        description = "Redis host";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 6379;
        description = "Redis port";
      };
    };

    storage = {
      consumeDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = if paths.hot.root != null then "${paths.hot.root}/documents/consume" else null;
        description = "Consume directory (drop zone for auto-import)";
      };

      exportDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = if paths.hot.root != null then "${paths.hot.root}/documents/export" else null;
        description = "Export directory";
      };

      stagingDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = if paths.hot.root != null then "${paths.hot.root}/documents/staging" else null;
        description = "Staging directory for pre-processing";
      };

      mediaDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = if paths.media.root != null then "${paths.media.root}/documents/paperless" else null;
        description = "Archive storage (originals, archive, thumbnails)";
      };

      dataDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = if paths.apps.root != null then "${paths.apps.root}/paperless/data" else null;
        description = "Paperless data directory (index, db cache)";
      };
    };

    ocr = {
      languages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "eng" ];
        description = "Tesseract OCR language codes";
      };

      outputType = lib.mkOption {
        type = lib.types.enum [ "pdf" "pdfa" "pdfa-2" ];
        default = "pdfa";
        description = "OCR output format (pdf, pdfa, pdfa-2)";
      };
    };

    consumer = {
      polling = lib.mkOption {
        type = lib.types.int;
        default = 60;
        description = "Seconds between consume folder scans";
      };

      deleteOriginals = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Delete originals after successful import";
      };
    };

    admin = {
      user = lib.mkOption {
        type = lib.types.str;
        default = "eric";
        description = "Initial admin username";
      };

      email = lib.mkOption {
        type = lib.types.str;
        default = "eric@hwc.local";
        description = "Initial admin email";
      };
    };

    reverseProxy = {
      path = lib.mkOption {
        type = lib.types.str;
        default = "/docs";
        description = "Reverse proxy subpath";
      };
    };

    resources = {
      memory = lib.mkOption {
        type = lib.types.str;
        default = "4g";
        description = "Memory limit for Paperless container";
      };

      cpus = lib.mkOption {
        type = lib.types.str;
        default = "2.0";
        description = "CPU limit for Paperless container";
      };
    };

    retention = {
      cleanup = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Paperless staging/export cleanup timer";
        };

        schedule = lib.mkOption {
          type = lib.types.str;
          default = "daily";
          description = "systemd OnCalendar schedule for cleanup";
        };

        stagingDays = lib.mkOption {
          type = lib.types.int;
          default = 7;
          description = "Delete staging files older than N days";
        };

        exportDays = lib.mkOption {
          type = lib.types.int;
          default = 30;
          description = "Delete export files older than N days";
        };
      };
    };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
    ./parts/directories.nix
  ];

  #=========================================================================
  # IMPLEMENTATION
  #=========================================================================
  config = lib.mkIf cfg.enable { };

  #=========================================================================
  # VALIDATION
  #=========================================================================
  # Add assertions and validation logic here
}
