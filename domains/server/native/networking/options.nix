# domains/server/networking/options.nix
#
# Consolidated options for server networking subdomain
# Charter-compliant: ALL networking options defined here

{ lib, config, ... }:

let
  paths = config.hwc.paths;
in
{
  #============================================================================
  # VPN OPTIONS
  #============================================================================
  options.hwc.services.vpn = {
    tailscale = {
      enable = lib.mkEnableOption "Tailscale VPN";

      authKeyFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to auth key file";
      };

      exitNode = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Act as exit node";
      };

      advertiseRoutes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Routes to advertise";
      };
    };

    wireguard = {
      enable = lib.mkEnableOption "WireGuard VPN";

      interfaces = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = {};
        description = "WireGuard interfaces";
      };
    };
  };

  #============================================================================
  # NTFY NOTIFICATION SERVICE OPTIONS
  #============================================================================
  options.hwc.services.ntfy = {
    enable = lib.mkEnableOption "ntfy notification service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "ntfy web port";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/ntfy";
      description = "Data directory";
    };
  };

  #============================================================================
  # TRANSCRIPT API OPTIONS
  #============================================================================
  options.hwc.services.transcriptApi = {
    enable = lib.mkEnableOption "YouTube transcript API";

    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "API port";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/home/eric/01-documents/01-vaults/04-transcripts";
      description = "Transcripts vault directory (where finished .md files are saved)";
    };

    apiKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "YouTube API keys";
    };
  };

  #============================================================================
  # DATABASES OPTIONS
  #============================================================================
  options.hwc.services.databases = {
    postgresql = {
      enable = lib.mkEnableOption "PostgreSQL database";

      version = lib.mkOption {
        type = lib.types.str;
        default = "15";
        description = "PostgreSQL version";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "${paths.state}/postgresql";
        description = "PostgreSQL data directory";
      };

      databases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Databases to create";
      };

      backup = {
        enable = lib.mkEnableOption "Automatic backups";

        schedule = lib.mkOption {
          type = lib.types.str;
          default = "daily";
          description = "Backup schedule";
        };
      };
    };

    redis = {
      enable = lib.mkEnableOption "Redis cache";

      port = lib.mkOption {
        type = lib.types.port;
        default = 6379;
        description = "Redis port";
      };

      maxMemory = lib.mkOption {
        type = lib.types.str;
        default = "2gb";
        description = "Maximum memory";
      };
    };

    influxdb = {
      enable = lib.mkEnableOption "InfluxDB time-series database";

      port = lib.mkOption {
        type = lib.types.port;
        default = 8086;
        description = "InfluxDB port";
      };
    };
  };

  #============================================================================
  # MEDIA NETWORKING OPTIONS
  #============================================================================
  options.hwc.services.media.networking = {
    enable = lib.mkEnableOption "media services networking and VPN";

    mediaNetwork = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "media-network";
        description = "Name of the media container network";
      };

      subnet = lib.mkOption {
        type = lib.types.str;
        default = "172.20.0.0/16";
        description = "Subnet for media container network";
      };

      driver = lib.mkOption {
        type = lib.types.str;
        default = "bridge";
        description = "Network driver for media services";
      };
    };

    vpn = {
      enable = lib.mkEnableOption "VPN container for download clients";

      provider = lib.mkOption {
        type = lib.types.enum [ "protonvpn" "nordvpn" "surfshark" "custom" ];
        default = "protonvpn";
        description = "VPN service provider";
      };

      image = lib.mkOption {
        type = lib.types.str;
        default = "qmcgaw/gluetun:latest";
        description = "Gluetun VPN container image";
      };

      serverCountries = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "Netherlands" ];
        description = "Preferred VPN server countries";
      };

      killSwitch = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable VPN kill switch";
      };

      extraEnvironment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional environment variables for VPN container";
      };
    };

    firewall = {
      allowMediaPorts = lib.mkEnableOption "open media service ports in firewall";

      vpnPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ 8080 8081 5030 ];
        description = "Ports exposed through VPN container";
      };
    };
  };
}