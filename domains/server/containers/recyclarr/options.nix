# modules/server/containers/recyclarr/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.recyclarr = {
    enable = mkEnableOption "Recyclarr *arr configuration sync";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/recyclarr/recyclarr:latest";
      description = "Container image for Recyclarr";
    };

    schedule = mkOption {
      type = types.str;
      default = "daily";
      description = "How often to sync configurations (daily, weekly, or systemd timer format)";
    };

    services = {
      sonarr = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Sync Sonarr configuration";
        };

        apiKeySecret = mkOption {
          type = types.str;
          default = "sonarr-api-key";
          description = "Agenix secret name for Sonarr API key";
        };
      };

      radarr = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Sync Radarr configuration";
        };

        apiKeySecret = mkOption {
          type = types.str;
          default = "radarr-api-key";
          description = "Agenix secret name for Radarr API key";
        };
      };

      lidarr = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Sync Lidarr configuration";
        };

        apiKeySecret = mkOption {
          type = types.str;
          default = "lidarr-api-key";
          description = "Agenix secret name for Lidarr API key";
        };
      };
    };
  };
}
