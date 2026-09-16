# domains/business/firefly/index.nix
#
# Firefly III Personal Finance Manager
# Includes both Firefly III core and Firefly-Pico mobile companion
{ lib, config, pkgs, inputs, ... }:

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
        default = "docker.io/fireflyiii/core:version-6.6.6";  # critical tier (Law 15 v12.4): financial data — pinned
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

    # Workbench Finance area: recurring-payment explorer backed by Firefly's
    # REST API. The service is socket-activated behind Caddy and never exposes
    # a TCP listener of its own.
    explorer = {
      enable = lib.mkEnableOption "Firefly recurring-payment explorer" // { default = true; };

      package = lib.mkOption {
        type = lib.types.package;
        default = inputs.pnc-statement-pipeline.packages.${pkgs.stdenv.hostPlatform.system}.default;
        defaultText = "inputs.pnc-statement-pipeline.packages.<system>.default";
        description = "Immutable Firefly Explorer application package.";
      };

      appUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://firefly-explorer.${config.hwc.networking.shared.vhostDomain}";
        description = "Public same-origin URL used for CSRF validation.";
      };

      patFile = lib.mkOption {
        type = lib.types.str;
        default = "/run/agenix/firefly-explorer-pat";
        description = "Dedicated Firefly personal access token path.";
      };

      socketPath = lib.mkOption {
        type = lib.types.str;
        default = "/run/firefly-explorer.sock";
        description = "Root-owned Unix socket used only by Caddy.";
      };

      assetAccountId = lib.mkOption {
        type = lib.types.ints.positive;
        default = 12;
        description = "Firefly asset-account id explored by this app.";
      };

      accountName = lib.mkOption {
        type = lib.types.str;
        default = "Dad - Checking";
        description = "Account label shown in the explorer.";
      };

      historyStart = lib.mkOption {
        type = lib.types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}";
        default = "2019-08-19";
        description = "Earliest Firefly date fetched for recurrence analysis.";
      };

      allowedLogin = lib.mkOption {
        type = lib.types.str;
        default = "eriqueo@github";
        description = "Exact Tailscale WhoIs LoginName allowed to use the API.";
      };

      cacheSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 60;
        description = "Bounded in-memory Firefly read cache lifetime.";
      };

      protectedTags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "dad-pnc-statements" ];
        description = "Existing Firefly tags the explorer may never remove.";
      };

      coverageNote = lib.mkOption {
        type = lib.types.str;
        default = "Firefly includes imported activity from August 2019, with known bank-source gaps after 2023-12-18 and in early 2025 and early 2026.";
        description = "Visible warning explaining the limits of imported history.";
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
    ./parts/explorer.nix
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
