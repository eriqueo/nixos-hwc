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