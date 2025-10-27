{ lib, config, ... }:
let
  cfg = config.hwc.features.media;
in
{
  options.hwc.features.media = {
    enable = lib.mkEnableOption "media services (Jellyfin, *arr stack)";
  };

  config = lib.mkIf cfg.enable {
    #==========================================================================
    # MEDIA STORAGE - Storage configuration for media services
    #==========================================================================
    hwc.infrastructure.storage = {
      media = {
        enable = true;
        directories = [
          "movies" "tv" "music" "books"
          "downloads" "incomplete"
        ];
      };
      hot.enable = true;
    };

    # NOTE: *arr stack containers (prowlarr, sonarr, radarr, lidarr) are enabled
    # in the server profile. This media profile focuses on Jellyfin and storage.

    # Jellyfin will be enabled when the appropriate container service is added
    # For now, this profile just ensures media storage is properly configured
  };
}
