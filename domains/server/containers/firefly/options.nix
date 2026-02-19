# domains/server/containers/firefly/options.nix
#
# Firefly III Personal Finance Manager Options
# Includes both Firefly III core and Firefly-Pico mobile companion
{ lib, config, ... }:

let
  inherit (lib) mkEnableOption mkOption types;
  paths = config.hwc.paths;
in
{
  options.hwc.server.containers.firefly = {
    enable = mkEnableOption "Firefly III personal finance manager (containerized)";

    # Container images
    images = {
      core = mkOption {
        type = types.str;
        default = "fireflyiii/core:latest";
        description = "Firefly III core container image";
      };

      pico = mkOption {
        type = types.str;
        default = "cioraneanu/firefly-pico:latest";
        description = "Firefly-Pico mobile companion container image";
      };
    };

    # Firefly III settings
    settings = {
      appUrl = mkOption {
        type = types.str;
        default = "https://hwc.ocelot-wahoo.ts.net:10443";
        description = "External URL for Firefly III (used for OAuth and redirects)";
      };

      timezone = mkOption {
        type = types.str;
        default = "America/Denver";
        description = "Timezone for Firefly III";
      };

      locale = mkOption {
        type = types.str;
        default = "en_US";
        description = "Default locale for Firefly III";
      };

      trustedProxies = mkOption {
        type = types.str;
        default = "**";
        description = ''
          Trusted proxy configuration.
          "**" trusts all proxies (safe behind Tailscale).
        '';
      };
    };

    # Firefly-Pico settings
    pico = {
      enable = mkEnableOption "Firefly-Pico mobile companion" // { default = true; };

      appUrl = mkOption {
        type = types.str;
        default = "https://hwc.ocelot-wahoo.ts.net:11443";
        description = "External URL for Firefly-Pico";
      };

      fireflyUrl = mkOption {
        type = types.str;
        default = "http://firefly:8080";
        description = "Internal URL to Firefly III (container network)";
      };
    };

    # Database configuration
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
        default = "firefly";
        description = "Database name for Firefly III";
      };

      picoName = mkOption {
        type = types.str;
        default = "firefly_pico";
        description = "Database name for Firefly-Pico";
      };

      user = mkOption {
        type = types.str;
        default = "eric";
        description = "Database user";
      };
    };

    # Storage configuration
    storage = {
      dataDir = mkOption {
        type = types.path;
        default = "${paths.apps.root}/firefly";
        description = "Data directory for Firefly III";
      };

      uploadDir = mkOption {
        type = types.path;
        default = "${paths.apps.root}/firefly/upload";
        description = "Upload directory for Firefly III attachments";
      };
    };

    # Reverse proxy configuration (port mode)
    reverseProxy = {
      corePort = mkOption {
        type = types.port;
        default = 10443;
        description = "External TLS port for Firefly III";
      };

      coreInternalPort = mkOption {
        type = types.port;
        default = 8085;
        description = "Internal HTTP port for Firefly III container";
      };

      picoPort = mkOption {
        type = types.port;
        default = 11443;
        description = "External TLS port for Firefly-Pico";
      };

      picoInternalPort = mkOption {
        type = types.port;
        default = 8086;
        description = "Internal HTTP port for Firefly-Pico container";
      };
    };

    # Network configuration
    network = {
      mode = mkOption {
        type = types.enum [ "media" "host" ];
        default = "media";
        description = "Network mode: media (podman network) or host";
      };
    };

    # Resource limits
    resources = {
      core = {
        memory = mkOption {
          type = types.str;
          default = "1g";
          description = "Memory limit for Firefly III container";
        };

        cpus = mkOption {
          type = types.str;
          default = "1.0";
          description = "CPU limit for Firefly III container";
        };
      };

      pico = {
        memory = mkOption {
          type = types.str;
          default = "512m";
          description = "Memory limit for Firefly-Pico container";
        };

        cpus = mkOption {
          type = types.str;
          default = "0.5";
          description = "CPU limit for Firefly-Pico container";
        };
      };
    };
  };
}
