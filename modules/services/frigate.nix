# nixos-hwc/modules/services/frigate.nix
#
# FRIGATE - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.services.frigate.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/services/frigate.nix
#
# USAGE:
#   hwc.services.frigate.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.frigate;
  paths = config.hwc.paths;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.services.frigate = {
    enable = lib.mkEnableOption "Frigate NVR";

    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "Web UI port";
    };

    rtspPort = lib.mkOption {
      type = lib.types.port;
      default = 8554;
      description = "RTSP server port";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.hot}/frigate";
      description = "Data directory";
    };

    enableGpu = lib.mkEnableOption "GPU acceleration for detection";

    enableCoral = lib.mkEnableOption "Coral TPU acceleration";

    cameras = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Camera configurations";
    };
  };


  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.frigate = {
      image = "ghcr.io/blakeblackshear/frigate:stable";

      ports = [
        "${toString cfg.port}:5000"
        "${toString cfg.rtspPort}:8554"
        "${toString cfg.rtspPort}:8555/tcp"
        "${toString cfg.rtspPort}:8555/udp"
      ];

      volumes = [
        "${cfg.dataDir}/config:/config"
        "${cfg.dataDir}/storage:/media/frigate"
        "/etc/localtime:/etc/localtime:ro"
        "tmpfs:/tmp/cache"
      ];

      environment = {
        FRIGATE_RTSP_PASSWORD = "password";  # Should come from secrets
        NVIDIA_VISIBLE_DEVICES = lib.mkIf cfg.enableGpu "all";
        NVIDIA_DRIVER_CAPABILITIES = lib.mkIf cfg.enableGpu "compute,video,utility";
      };

      extraOptions = [
        "--shm-size=256mb"
        "--device=/dev/dri"
        "--mount=type=tmpfs,destination=/tmp/cache,tmpfs-size=1000000000"
      ] ++ lib.optionals cfg.enableGpu [
        "--runtime=nvidia"
      ] ++ lib.optionals cfg.enableCoral [
        "--device=/dev/bus/usb"
        "--device=/dev/apex_0"
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/config 0755 root root -"
      "d ${cfg.dataDir}/storage 0755 root root -"
      "d ${cfg.dataDir}/storage/recordings 0755 root root -"
      "d ${cfg.dataDir}/storage/clips 0755 root root -"
    ];

    networking.firewall.allowedTCPPorts = [ cfg.port cfg.rtspPort 8555 ];
    networking.firewall.allowedUDPPorts = [ cfg.rtspPort 8555 ];
  };
}
