{ lib, config, pkgs, ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.recyclarr = {
    enable = lib.mkEnableOption "Recyclarr *arr configuration sync";
    image = lib.mkOption { type = lib.types.str; default = "ghcr.io/recyclarr/recyclarr:latest"; description = "Container image for Recyclarr"; };
    schedule = lib.mkOption { type = lib.types.str; default = "daily"; description = "How often to sync configurations"; };
    services = {
      sonarr = {
        enable = lib.mkOption { type = lib.types.bool; default = true; description = "Sync Sonarr configuration"; };
        apiKeySecret = lib.mkOption { type = lib.types.str; default = "sonarr-api-key"; description = "Agenix secret name for Sonarr API key"; };
      };
      radarr = {
        enable = lib.mkOption { type = lib.types.bool; default = true; description = "Sync Radarr configuration"; };
        apiKeySecret = lib.mkOption { type = lib.types.str; default = "radarr-api-key"; description = "Agenix secret name for Radarr API key"; };
      };
      lidarr = {
        enable = lib.mkOption { type = lib.types.bool; default = true; description = "Sync Lidarr configuration"; };
        apiKeySecret = lib.mkOption { type = lib.types.str; default = "lidarr-api-key"; description = "Agenix secret name for Lidarr API key"; };
      };
    };
  };

  imports = [
    ./parts/config.nix
    ./parts/setup.nix
  ];
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};

  #==========================================================================
  # VALIDATION
  #==========================================================================
    config.assertions = lib.mkIf (config ? enable && config.enable) [];

}
