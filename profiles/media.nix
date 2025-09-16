{ ... }:
{
  imports = [
    ../modules/infrastructure/index.nix
    ../modules/server/jellyfin.nix
    ../modules/server/arr-stack.nix
  ];
  
  hwc.infrastructure.hardware.storage = {
    media = {
      enable = true;
      directories = [
        "movies" "tv" "music" "books"
        "downloads" "incomplete"
      ];
    };
    hot.enable = true;
  };
  
  hwc.services.jellyfin = {
    enable = true;
    enableGpu = true;
    openFirewall = true;
  };
  
  hwc.services.arrStack = {
    enable = true;
    sonarr.enable = true;
    radarr.enable = true;
    prowlarr.enable = true;
    bazarr.enable = true;
  };
}
