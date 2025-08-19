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
      description = "Data directory for Jellyfin";
    };

    mediaDir = lib.mkOption {
      type = lib.types.path;
      default = paths.media;
      description = "Media library path";
    };

    enableGpu = lib.mkEnableOption "GPU hardware acceleration";

    enableVaapi = lib.mkEnableOption "VAAPI acceleration";
  };

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.jellyfin = {
      image = "jellyfin/jellyfin:latest";

      ports = [
        "${toString cfg.port}:8096"
        "8920:8920"  # HTTPS
        "7359:7359/udp"  # Discovery
        "1900:1900/udp"  # DLNA
      ];

      volumes = [
        "${cfg.dataDir}/config:/config"
        "${cfg.dataDir}/cache:/cache"
        "${cfg.mediaDir}:/media:ro"
        "/etc/localtime:/etc/localtime:ro"
      ];

      environment = {
        JELLYFIN_PublishedServerUrl = "http://jellyfin.hwc.moe";
        TZ = "America/Denver";
        JELLYFIN_FFmpeg__probesize = "50000000";
        JELLYFIN_FFmpeg__analyzeduration = "50000000";
      };

      extraOptions =
        lib.optionals cfg.enableGpu [
          "--device=/dev/dri"
          "--device=/dev/nvidia0"
          "--device=/dev/nvidiactl"
          "--device=/dev/nvidia-uvm"
          "--runtime=nvidia"
        ] ++
        lib.optionals cfg.enableVaapi [
          "--device=/dev/dri/renderD128"
        ];
    };

    # Ensure directories exist
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/config 0755 root root -"
      "d ${cfg.dataDir}/cache 0755 root root -"
    ];

    # GPU support
    hardware.nvidia-container-toolkit.enable = cfg.enableGpu;

    # Firewall rules
    networking.firewall.allowedTCPPorts = [ cfg.port 8920 ];
    networking.firewall.allowedUDPPorts = [ 7359 1900 ];
  };
}
