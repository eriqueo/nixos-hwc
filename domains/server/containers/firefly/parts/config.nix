# domains/server/containers/firefly/parts/config.nix
#
# Firefly III Container Configuration
# Containerized personal finance manager with Firefly-Pico mobile companion
{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.server.containers.firefly;
  paths = config.hwc.paths;
  appsRoot = paths.apps.root;
  fireflyRoot = "${appsRoot}/firefly";
  fireflyUpload = "${fireflyRoot}/upload";
  fireflyPicoRoot = "${fireflyRoot}/pico";

  # Network configuration
  mediaNetworkName = "media-network";
  networkOpts = if cfg.network.mode == "media"
    then [ "--network=${mediaNetworkName}" ]
    else [ "--network=host" ];

  # Secret file path
  appKeyFile = config.age.secrets.firefly-app-key.path;
in
{
  config = lib.mkIf cfg.enable {

    #=========================================================================
    # STORAGE DIRECTORIES
    #=========================================================================
    systemd.tmpfiles.rules = [
      # Firefly III directories
      "d ${fireflyRoot} 0750 eric users -"
      "d ${fireflyUpload} 0750 eric users -"
    ] ++ lib.optionals cfg.pico.enable [
      # Firefly-Pico directories
      "d ${fireflyPicoRoot} 0750 eric users -"
    ];

    #=========================================================================
    # FIREFLY III CORE CONTAINER
    #=========================================================================
    virtualisation.oci-containers.containers.firefly = {
      image = cfg.images.core;
      autoStart = true;

      extraOptions = networkOpts ++ [
        "--network-alias=firefly"
        "--memory=${cfg.resources.core.memory}"
        "--cpus=${cfg.resources.core.cpus}"
        "--memory-swap=2g"
      ];

      # Expose port for external access
      ports = if cfg.network.mode != "host" then [
        "127.0.0.1:${toString cfg.reverseProxy.coreInternalPort}:8080"
      ] else [];

      environment = {
        # ================================================================
        # CORE CONFIGURATION
        # ================================================================
        PUID = "1000";
        PGID = "100";
        TZ = cfg.settings.timezone;

        # App URL (for OAuth, redirects, etc.)
        APP_URL = cfg.settings.appUrl;
        TRUSTED_PROXIES = cfg.settings.trustedProxies;

        # Locale
        DEFAULT_LOCALE = cfg.settings.locale;
        DEFAULT_LANGUAGE = "en_US";

        # ================================================================
        # DATABASE CONFIGURATION
        # ================================================================
        DB_CONNECTION = "pgsql";
        DB_HOST = cfg.database.host;
        DB_PORT = toString cfg.database.port;
        DB_DATABASE = cfg.database.name;
        DB_USERNAME = cfg.database.user;
        # No password needed - using peer/trust auth for eric user

        # ================================================================
        # CACHE AND SESSION
        # ================================================================
        CACHE_DRIVER = "file";
        SESSION_DRIVER = "file";

        # ================================================================
        # SECURITY
        # ================================================================
        # APP_KEY is loaded via entrypoint script from secret file
        APP_KEY_FILE = "/run/secrets/app-key";
      };

      volumes = [
        "${fireflyUpload}:/var/www/html/storage/upload:rw"
        "${appKeyFile}:/run/secrets/app-key:ro"
      ];
    };

    #=========================================================================
    # FIREFLY-PICO MOBILE COMPANION CONTAINER
    #=========================================================================
    virtualisation.oci-containers.containers.firefly-pico = lib.mkIf cfg.pico.enable {
      image = cfg.images.pico;
      autoStart = true;
      dependsOn = [ "firefly" ];

      extraOptions = networkOpts ++ [
        "--network-alias=firefly-pico"
        "--memory=${cfg.resources.pico.memory}"
        "--cpus=${cfg.resources.pico.cpus}"
        "--memory-swap=1g"
      ];

      # Expose port for external access
      ports = if cfg.network.mode != "host" then [
        "127.0.0.1:${toString cfg.reverseProxy.picoInternalPort}:80"
      ] else [];

      environment = {
        # ================================================================
        # CORE CONFIGURATION
        # ================================================================
        TZ = cfg.settings.timezone;

        # ================================================================
        # FIREFLY CONNECTION
        # ================================================================
        # Pico connects to Firefly III via container network
        FIREFLY_URL = cfg.pico.fireflyUrl;

        # ================================================================
        # DATABASE CONFIGURATION (Pico has its own DB)
        # ================================================================
        DB_CONNECTION = "pgsql";
        DB_HOST = cfg.database.host;
        DB_PORT = toString cfg.database.port;
        DB_DATABASE = cfg.database.picoName;
        DB_USERNAME = cfg.database.user;
      };

      volumes = [
        "${fireflyPicoRoot}:/app/storage:rw"
      ];
    };

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    systemd.services = {
      "podman-firefly" = {
        after = [ "network-online.target" "postgresql.service" ]
          ++ lib.optional (cfg.network.mode == "media") "init-media-network.service";
        wants = [ "network-online.target" ];
        serviceConfig = {
          # Ensure the APP_KEY secret is readable
          SupplementaryGroups = [ "secrets" ];
        };
      };

      "podman-firefly-pico" = lib.mkIf cfg.pico.enable {
        after = [ "network-online.target" "postgresql.service" "podman-firefly.service" ]
          ++ lib.optional (cfg.network.mode == "media") "init-media-network.service";
        wants = [ "network-online.target" ];
      };
    };

    #=========================================================================
    # FIREWALL CONFIGURATION
    #=========================================================================
    # Open firewall ports only on Tailscale interface (not public)
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      cfg.reverseProxy.coreInternalPort
    ] ++ lib.optionals cfg.pico.enable [
      cfg.reverseProxy.picoInternalPort
    ];

    #=========================================================================
    # DATABASE REGISTRATION
    #=========================================================================
    # Register databases with PostgreSQL service
    hwc.server.databases.postgresql.databases = [
      cfg.database.name
    ] ++ lib.optionals cfg.pico.enable [
      cfg.database.picoName
    ];

    #=========================================================================
    # VALIDATION
    #=========================================================================
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
  };
}
