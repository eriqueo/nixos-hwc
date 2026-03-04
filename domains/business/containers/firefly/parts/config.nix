# domains/server/containers/firefly/parts/config.nix
#
# Firefly III Container Configuration
# Containerized personal finance manager with Firefly-Pico mobile companion
{ lib, config, pkgs, ... }:

let
  # Import PURE helper library
  helpers = import ../../../../lib/mkContainer.nix { inherit lib pkgs; };
  inherit (helpers) mkContainer;

  cfg = config.hwc.server.containers.firefly;
  paths = config.hwc.paths;
  appsRoot = paths.apps.root;
  fireflyRoot = "${appsRoot}/firefly";
  fireflyUpload = "${fireflyRoot}/upload";
  fireflyPicoRoot = "${fireflyRoot}/pico";
  fireflyEnvFile = "${fireflyRoot}/.env";

  # Network configuration
  mediaNetworkName = "media-network";

  # Secret file path
  appKeyFile = config.age.secrets.firefly-app-key.path;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    #=========================================================================
    # STORAGE DIRECTORIES
    #=========================================================================
    {
      systemd.tmpfiles.rules = [
        "d ${fireflyRoot} 0755 eric users -"
        "d ${fireflyUpload} 0777 eric users -"
      ] ++ lib.optionals cfg.pico.enable [
        "d ${fireflyPicoRoot} 0755 eric users -"
      ];
    }

    #=========================================================================
    # FIREFLY III CORE CONTAINER
    #=========================================================================
    (mkContainer {
      name = "firefly";
      image = cfg.images.core;
      networkMode = if cfg.network.mode == "media" then "media" else "host";
      gpuEnable = false;
      timeZone = cfg.settings.timezone;

      # Resource limits
      memory = cfg.resources.core.memory;
      cpus = cfg.resources.core.cpus;
      memorySwap = "2g";

      # Environment files for APP_KEY
      environmentFiles = [ fireflyEnvFile ];

      # Extra options for network alias
      extraOptions = lib.optionals (cfg.network.mode != "host") [
        "--network-alias=firefly"
      ];

      ports = lib.optionals (cfg.network.mode != "host") [
        "127.0.0.1:${toString cfg.reverseProxy.coreInternalPort}:8080"
      ];

      environment = {
        # App URL (for OAuth, redirects, etc.)
        APP_URL = cfg.settings.appUrl;
        TRUSTED_PROXIES = cfg.settings.trustedProxies;

        # Locale
        DEFAULT_LOCALE = cfg.settings.locale;
        DEFAULT_LANGUAGE = "en_US";

        # Database configuration
        DB_CONNECTION = "pgsql";
        DB_HOST = cfg.database.host;
        DB_PORT = toString cfg.database.port;
        DB_DATABASE = cfg.database.name;
        DB_USERNAME = cfg.database.user;

        # Cache and session
        CACHE_DRIVER = "file";
        SESSION_DRIVER = "file";
      };

      volumes = [
        "${fireflyUpload}:/var/www/html/storage/upload:rw"
      ];
    })

    #=========================================================================
    # FIREFLY-PICO MOBILE COMPANION CONTAINER
    #=========================================================================
    (lib.mkIf cfg.pico.enable (mkContainer {
      name = "firefly-pico";
      image = cfg.images.pico;
      networkMode = if cfg.network.mode == "media" then "media" else "host";
      gpuEnable = false;
      timeZone = cfg.settings.timezone;

      # Resource limits
      memory = cfg.resources.pico.memory;
      cpus = cfg.resources.pico.cpus;
      memorySwap = "1g";

      # Extra options for network alias
      extraOptions = lib.optionals (cfg.network.mode != "host") [
        "--network-alias=firefly-pico"
      ];

      ports = lib.optionals (cfg.network.mode != "host") [
        "127.0.0.1:${toString cfg.reverseProxy.picoInternalPort}:80"
      ];

      environment = {
        # Firefly connection
        FIREFLY_URL = cfg.pico.fireflyUrl;

        # Database configuration
        DB_CONNECTION = "pgsql";
        DB_HOST = cfg.database.host;
        DB_PORT = toString cfg.database.port;
        DB_DATABASE = cfg.database.picoName;
        DB_USERNAME = cfg.database.user;
      };

      volumes = [
        "${fireflyPicoRoot}:/app/storage:rw"
      ];

      dependsOn = [ "firefly" ];
    }))

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    {
      systemd.services = {
        "podman-firefly" = {
          after = [ "network-online.target" "postgresql.service" ]
            ++ lib.optional (cfg.network.mode == "media") "init-media-network.service";
          wants = [ "network-online.target" ];
          serviceConfig = {
            SupplementaryGroups = [ "secrets" ];
          };
          # Generate env file with APP_KEY from agenix secret
          preStart = lib.mkAfter ''
            APP_KEY=$(cat ${appKeyFile})
            echo "APP_KEY=base64:$APP_KEY" > ${fireflyEnvFile}
            chmod 644 ${fireflyEnvFile}
          '';
        };

        "podman-firefly-pico" = lib.mkIf cfg.pico.enable {
          after = [ "network-online.target" "postgresql.service" "podman-firefly.service" ]
            ++ lib.optional (cfg.network.mode == "media") "init-media-network.service";
          wants = [ "network-online.target" ];
        };
      };
    }

    #=========================================================================
    # FIREWALL CONFIGURATION
    #=========================================================================
    {
      networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
        cfg.reverseProxy.coreInternalPort
      ] ++ lib.optionals cfg.pico.enable [
        cfg.reverseProxy.picoInternalPort
      ];
    }

    #=========================================================================
    # DATABASE REGISTRATION
    #=========================================================================
    {
      hwc.server.databases.postgresql.databases = [
        cfg.database.name
      ] ++ lib.optionals cfg.pico.enable [
        cfg.database.picoName
      ];
    }

    #=========================================================================
    # VALIDATION
    #=========================================================================
    {
      assertions = [
        {
          assertion = !cfg.enable || config.hwc.server.databases.postgresql.enable;
          message = "hwc.server.containers.firefly requires PostgreSQL to be enabled (hwc.server.databases.postgresql.enable = true)";
        }
        {
          assertion = !cfg.enable || config.age.secrets ? firefly-app-key;
          message = "hwc.server.containers.firefly requires firefly-app-key secret to be defined in domains/secrets/declarations/server.nix";
        }
        {
          assertion = cfg.reverseProxy.corePort != cfg.reverseProxy.picoPort;
          message = "Firefly III and Firefly-Pico must use different external TLS ports";
        }
        {
          assertion = cfg.reverseProxy.coreInternalPort != cfg.reverseProxy.picoInternalPort;
          message = "Firefly III and Firefly-Pico must use different internal ports";
        }
      ];
    }
  ]);
}
