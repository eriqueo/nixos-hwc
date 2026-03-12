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
        default = "docker.io/fireflyiii/core:latest";
        description = "Firefly III core container image";
      };

      pico = lib.mkOption {
        type = lib.types.str;
        default = "cioraneanu/firefly-pico:latest";
        description = "Firefly-Pico mobile companion container image";
      };
    };

    # Firefly III settings
    settings = {
      appUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://hwc.ocelot-wahoo.ts.net:10443";
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
        default = "https://hwc.ocelot-wahoo.ts.net:11443";
        description = "External URL for Firefly-Pico";
      };

      fireflyUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://firefly:8080";
        description = "Internal URL to Firefly III (container network)";
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
