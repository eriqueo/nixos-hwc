# domains/business/firefly/index.nix
#
# Firefly III Personal Finance Manager
# Includes both Firefly III core and Firefly-Pico mobile companion
{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.business.firefly;
  paths = config.hwc.paths;
in
{
  # OPTIONS
  options.hwc.business.firefly = {
    enable = lib.mkEnableOption "Firefly III personal finance manager (containerized)";

    # Container images
    images = {
      core = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/fireflyiii/core:version-6.4.22";  # critical tier (Law 15 v12.4): financial data — pinned
        description = "Firefly III core container image";
      };

      pico = lib.mkOption {
        type = lib.types.str;
        default = "cioraneanu/firefly-pico:1.10.1";  # critical tier (Law 15 v12.4): financial data — pinned
        description = "Firefly-Pico mobile companion container image";
      };

      importer = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/fireflyiii/data-importer:version-2.3.4";  # critical tier (Law 15 v12.4): financial data — pinned
        description = "Firefly III data importer container image";
      };
    };

    # Firefly III settings
    settings = {
      appUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://firefly.${config.hwc.networking.shared.vhostDomain}";
        description = "External URL for Firefly III (used for OAuth and redirects)";
      };

      timezone = lib.mkOption {
        type = lib.types.str;
        default = "America/Denver";
        description = "Timezone for Firefly III";
      };

      locale = lib.mkOption {
        type = lib.types.str;
        default = "en_US";
        description = "Default locale for Firefly III";
      };

      trustedProxies = lib.mkOption {
        type = lib.types.str;
        default = "**";
        description = ''
          Trusted proxy configuration.
          "**" trusts all proxies (safe behind Tailscale).
        '';
      };
    };

    # Firefly-Pico settings
    pico = {
      enable = lib.mkEnableOption "Firefly-Pico mobile companion" // { default = true; };

      appUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://firefly-pico.${config.hwc.networking.shared.vhostDomain}";
        description = "External URL for Firefly-Pico";
      };

      fireflyUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://firefly:8080";
        description = "Internal URL to Firefly III (container network)";
      };
    };

    # Data importer (CSV / SimpleFIN / GoCardless → Firefly III)
    importer = {
      enable = lib.mkEnableOption "Firefly III data importer" // { default = true; };

      appUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://firefly-import.${config.hwc.networking.shared.vhostDomain}";
        description = "External URL for the data importer";
      };

      fireflyUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://firefly:8080";
        description = "Internal URL to Firefly III (container network)";
      };

      internalPort = lib.mkOption {
        type = lib.types.port;
        default = 8087;
        description = "Internal HTTP port for the data importer container";
      };
    };

    # Automation timers (cron + daily digest into hwc-notify)
    automation = {
      cron = {
        enable = lib.mkEnableOption "Firefly III daily cron (recurring transactions, bills, auto-budgets)" // { default = true; };

        onCalendar = lib.mkOption {
          type = lib.types.str;
          default = "*-*-* 03:10:00";
          description = "systemd OnCalendar spec for the Firefly cron hit";
        };
      };

      digest = {
        enable = lib.mkEnableOption "daily finance digest posted to hwc-notify" // { default = true; };

        onCalendar = lib.mkOption {
          type = lib.types.str;
          default = "*-*-* 07:15:00";
          description = "systemd OnCalendar spec for the finance digest";
        };

        patFile = lib.mkOption {
          type = lib.types.str;
          default = "/run/agenix/firefly-pat";
          description = ''
            Path to a Firefly III personal access token. The digest exits
            cleanly (with a journal note) until this file exists, so the
            timer can ship before the token is provisioned.
          '';
        };
      };
    };

    # Database configuration
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
        default = "firefly";
        description = "Database name for Firefly III";
      };

      picoName = lib.mkOption {
        type = lib.types.str;
        default = "firefly_pico";
        description = "Database name for Firefly-Pico";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "eric";
        description = "Database user";
      };
    };

    # Storage configuration
    storage = {
      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "${paths.apps.root}/firefly";
        description = "Data directory for Firefly III";
      };

      uploadDir = lib.mkOption {
        type = lib.types.path;
        default = "${paths.apps.root}/firefly/upload";
        description = "Upload directory for Firefly III attachments";
      };
    };

    # Reverse proxy configuration (port mode)
    reverseProxy = {
      corePort = lib.mkOption {
        type = lib.types.port;
        default = 10443;
        description = "External TLS port for Firefly III";
      };

      coreInternalPort = lib.mkOption {
        type = lib.types.port;
        default = 8085;
        description = "Internal HTTP port for Firefly III container";
      };

      picoPort = lib.mkOption {
        type = lib.types.port;
        default = 11443;
        description = "External TLS port for Firefly-Pico";
      };

      picoInternalPort = lib.mkOption {
        type = lib.types.port;
        default = 8086;
        description = "Internal HTTP port for Firefly-Pico container";
      };
    };

    # Network configuration
    network = {
      mode = lib.mkOption {
        type = lib.types.enum [ "media" "host" ];
        default = "media";
        description = "Network mode: media (podman network) or host";
      };
    };

    # Resource limits
    resources = {
      core = {
        memory = lib.mkOption {
          type = lib.types.str;
          default = "1g";
          description = "Memory limit for Firefly III container";
        };

        cpus = lib.mkOption {
          type = lib.types.str;
          default = "1.0";
          description = "CPU limit for Firefly III container";
        };
      };

      pico = {
        memory = lib.mkOption {
          type = lib.types.str;
          default = "512m";
          description = "Memory limit for Firefly-Pico container";
        };

        cpus = lib.mkOption {
          type = lib.types.str;
          default = "0.5";
          description = "CPU limit for Firefly-Pico container";
        };
      };
    };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
    ./parts/automation.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable { };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Assertions are defined in parts/config.nix alongside the implementation
}
