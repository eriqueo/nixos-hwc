{ lib, osConfig ? {}, ...}:

{
  options.hwc.home.apps.jellyfin-media-player = {
    enable = lib.mkEnableOption "Enable Jellyfin Media Player (desktop client).";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Start Jellyfin Media Player automatically on login (user service).";
    };
  };
}