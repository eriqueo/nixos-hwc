{ ... }:
{
  imports = [
    ../modules/infrastructure/storage.nix
    ../modules/services/jellyfin.nix
    ../modules/services/arr-stack.nix
  ];
  
  hwc.storage = {
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
