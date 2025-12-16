{ lib, ... }:

{
  options.hwc.features.media = {
    enable = lib.mkEnableOption "media services (Jellyfin, *arr stack)";
  };
}
