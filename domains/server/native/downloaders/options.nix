# domains/server/downloaders/options.nix
#
# Consolidated options for server downloaders subdomain
# Charter-compliant: ALL downloaders options defined here

{ lib, config, ... }:

let
  cfg = config.hwc.server.native.downloaders;
in
{
  options.hwc.server.native.downloaders = {
    enable = lib.mkEnableOption "media download clients";

    #==========================================================================
    # NETWORK CONFIGURATION
    #==========================================================================
    useVpn = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Route download traffic through VPN container";
    };

    networkName = lib.mkOption {
      type = lib.types.str;
      default = "media-network";
      description = "Container network name when not using VPN";
    };

    #==========================================================================
    # QBITTORRENT TORRENT CLIENT
    #==========================================================================
    qbittorrent = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Enable qBittorrent torrent client";
      };

      image = lib.mkOption {
        type = lib.types.str;
        default = "lscr.io/linuxserver/qbittorrent:latest";
        description = "qBittorrent container image";
      };

      webPort = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "qBittorrent web UI port";
      };

      extraEnvironment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional environment variables";
      };
    };

    #==========================================================================
    # SABNZBD USENET CLIENT
    #==========================================================================
    sabnzbd = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Enable SABnzbd usenet client";
      };

      image = lib.mkOption {
        type = lib.types.str;
        default = "lscr.io/linuxserver/sabnzbd:latest";
        description = "SABnzbd container image";
      };

      webPort = lib.mkOption {
        type = lib.types.port;
        default = 8081;
        description = "SABnzbd web UI port";
      };

      extraEnvironment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional environment variables";
      };
    };

    #==========================================================================
    # SLSKD SOULSEEK CLIENT
    #==========================================================================
    slskd = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Enable SLSKD Soulseek client";
      };

      image = lib.mkOption {
        type = lib.types.str;
        default = "slskd/slskd:latest";
        description = "SLSKD container image";
      };

      webPort = lib.mkOption {
        type = lib.types.port;
        default = 5030;
        description = "SLSKD web UI port";
      };

      username = lib.mkOption {
        type = lib.types.str;
        default = "eriqueok";
        description = "SLSKD web username";
      };

      slskUsername = lib.mkOption {
        type = lib.types.str;
        default = "eriqueok";
        description = "Soulseek network username";
      };

      useSecrets = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use secrets for SLSKD passwords";
      };

      extraEnvironment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional environment variables";
      };
    };

    #==========================================================================
    # SOULARR AUTOMATION
    #==========================================================================
    soularr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable && cfg.slskd.enable;
        description = "Enable Soularr automation for SLSKD/Lidarr";
      };

      image = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/mrusse08/soularr:latest";
        description = "Soularr container image";
      };

      extraEnvironment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional environment variables";
      };
    };
  };
}