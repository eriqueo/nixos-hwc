{ ... }:
{
  #==========================================================================
  # BASE SYSTEM - Critical for machine functionality
  #==========================================================================
  imports = [
    ../domains/infrastructure/index.nix
    ../domains/server/jellyfin.nix
    ../domains/server/arr-stack.nix
  ];

  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================
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
