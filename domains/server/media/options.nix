{ lib, ... }:

{
  options.hwc.server.media = {
    enable = lib.mkEnableOption "media services (Jellyfin, *arr stack)";
  };
}
