{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.jellyfin;
  paths = config.hwc.paths;
in {
  options.hwc.services.jellyfin = {
    enable = lib.mkEnableOption "Jellyfin media server";
    
    port = lib.mkOption {
      type = lib.types.port;
      default = 8096;
      description = "Web UI port";
    };
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.hot}/jellyfin";
      description = "Data directory";
    };
    
    mediaDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.hwc.storage.media.path}";
      description = "Media library path";
    };
    
    enableGpu = lib.mkEnableOption "GPU transcoding";
    
    enableVaapi = lib.mkEnableOption "VAAPI acceleration";
    
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall ports";
    };
  };
  
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.jellyfin = {
      image = "jellyfin/jellyfin:latest";
      
      ports = [
        "${toString cfg.port}:8096"
        "8920:8920"
        "7359:7359/udp"
        "1900:1900/udp"
      ];
      
      volumes = [
        "${cfg.dataDir}/config:/config"
        "${cfg.dataDir}/cache:/cache"
        "${cfg.mediaDir}:/media:ro"
      ];
      
      environment = {
        JELLYFIN_PublishedServerUrl = "http://jellyfin.local";
        TZ = config.time.timeZone;
      };
      
      extraOptions = lib.optionals cfg.enableGpu [
        "--device=/dev/dri"
        "--runtime=nvidia"
        "--gpus=all"
      ] ++ lib.optionals cfg.enableVaapi [
        "--device=/dev/dri/renderD128"
      ];
    };
    
    hardware.nvidia-container-toolkit.enable = cfg.enableGpu;
    
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/config 0755 root root -"
      "d ${cfg.dataDir}/cache 0755 root root -"
    ];
    
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port 8920 ];
      allowedUDPPorts = [ 7359 1900 ];
    };
  };
}
