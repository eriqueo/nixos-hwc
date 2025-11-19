{ lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.hwc.server.immich = {
    enable = mkEnableOption "Immich photo management server (native service)";

    settings = {
      host = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Listen address for Immich server";
      };

      port = mkOption {
        type = types.port;
        default = 2283;
        description = "Port for Immich server";
      };

      mediaLocation = mkOption {
        type = types.str;
        default = "/mnt/photos";
        description = "Path to media storage location";
      };
    };

    storage = {
      enable = mkEnableOption "Advanced storage layout with separate directories" // { default = true; };

      basePath = mkOption {
        type = types.str;
        default = "/mnt/photos";
        description = ''
          Base path for all Immich storage. All storage subdirectories will be created here.
          This path will be added to backup sources automatically.
        '';
      };

      locations = {
        library = mkOption {
          type = types.str;
          default = "/mnt/photos/library";
          description = ''
            Primary photo/video library location (UPLOAD_LOCATION).
            Storage templates configured via web UI organize files within this directory.
            Recommended storage template: {{y}}/{{MM}}/{{dd}}/{{filename}}
          '';
        };

        thumbs = mkOption {
          type = types.str;
          default = "/mnt/photos/thumbs";
          description = "Thumbnail cache location (THUMB_LOCATION)";
        };

        encodedVideo = mkOption {
          type = types.str;
          default = "/mnt/photos/encoded-video";
          description = "Transcoded video storage (ENCODED_VIDEO_LOCATION)";
        };

        profile = mkOption {
          type = types.str;
          default = "/mnt/photos/profile";
          description = "User profile pictures (PROFILE_LOCATION)";
        };
      };

      template = {
        recommended = mkOption {
          type = types.str;
          default = "{{y}}/{{MM}}/{{dd}}/{{filename}}";
          description = ''
            Recommended storage template (configure via web UI after installation).
            This organizes files by: Year/Month/Day/Filename

            Available template variables:
            - {{y}} - Year (4 digits)
            - {{yy}} - Year (2 digits)
            - {{MM}} - Month (01-12)
            - {{MMM}} - Month (Jan-Dec)
            - {{dd}} - Day (01-31)
            - {{hh}} - Hour (00-23)
            - {{mm}} - Minute (00-59)
            - {{ss}} - Second (00-59)
            - {{filename}} - Original filename
            - {{ext}} - File extension
            - {{album}} - Album name (if in album)

            Alternative templates:
            - Multi-user organized: {{y}}/{{MM}}/{{album}}/{{filename}}
            - Camera-based: {{y}}/{{MM}}/{{assetId}}/{{filename}}
            - Simple monthly: {{y}}/{{MM}}/{{filename}}
          '';
        };

        documentation = mkOption {
          type = types.str;
          default = ''
            Storage templates are configured via the Immich web UI:
            1. Log in as admin
            2. Navigate to Administration → Settings → Storage Template
            3. Use the template builder to configure your preferred structure
            4. Test the template before applying
            5. Existing files can be migrated to the new template structure

            IMPORTANT: Storage templates only affect NEW uploads. Use the migration
            job in the web UI to reorganize existing files.
          '';
          description = "Documentation for configuring storage templates";
        };
      };
    };

    backup = {
      enable = mkEnableOption "Immich data backup integration" // { default = true; };

      includeDatabase = mkOption {
        type = types.bool;
        default = true;
        description = "Include PostgreSQL database dumps in backups";
      };

      databaseBackupPath = mkOption {
        type = types.str;
        default = "/var/backup/immich-db";
        description = "Path for PostgreSQL database dumps";
      };

      schedule = mkOption {
        type = types.str;
        default = "daily";
        description = "Database backup schedule (daily/hourly)";
      };
    };

    database = {
      createDB = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to create database (false to use existing)";
      };

      name = mkOption {
        type = types.str;
        default = "immich";
        description = "Database name";
      };

      user = mkOption {
        type = types.str;
        default = "immich";
        description = "Database user";
      };
    };

    redis = {
      enable = mkEnableOption "Redis caching for Immich";
    };

    gpu = {
      enable = mkEnableOption "GPU acceleration for photo/video processing";
    };

    # Note: Immich uses direct port access, not reverse proxy (SvelteKit issues)
    directAccess = {
      tailscaleHttps = mkOption {
        type = types.str;
        default = "https://hwc.ocelot-wahoo.ts.net:2283";
        description = "Tailscale HTTPS access URL";
      };

      localHttp = mkOption {
        type = types.str;
        default = "http://192.168.1.13:2283";
        description = "Local HTTP access URL";
      };
    };
  };
}