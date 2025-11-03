{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.jellyfin;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Native Jellyfin service configuration
    services.jellyfin = {
      enable = true;
      openFirewall = cfg.openFirewall;
    };



    # Manual firewall configuration (matching /etc/nixos pattern)
    networking.firewall = lib.mkIf (!cfg.openFirewall) {
      allowedTCPPorts = [ 8096 7359 ];  # HTTP + TCP discovery
      allowedUDPPorts = [ 7359 ];       # UDP discovery
    };

    # GPU acceleration configuration (matching Immich pattern)
    systemd.services.jellyfin = lib.mkIf cfg.gpu.enable {
      serviceConfig = {
        # Add GPU device access for video transcoding
        DeviceAllow = [
          "/dev/nvidia0 rw"
          "/dev/nvidiactl rw"
          "/dev/nvidia-modeset rw"
          "/dev/nvidia-uvm rw"
          "/dev/nvidia-uvm-tools rw"
          "/dev/dri/card0 rw"
          "/dev/dri/renderD128 rw"
        ];
        # Add user to GPU groups for hardware access
        SupplementaryGroups = [ "video" "render" ];
      };
      environment = {
        # NVIDIA GPU acceleration for video transcoding
        NVIDIA_VISIBLE_DEVICES = "all";
        NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
        # Critical: Add library path for NVIDIA CUDA libraries
        LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
      };
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.reverseProxy.enable || config.hwc.services.reverseProxy.enable;
        message = "hwc.server.jellyfin.reverseProxy requires hwc.services.reverseProxy.enable = true";
      }
      {
        assertion = !cfg.gpu.enable || config.hwc.infrastructure.hardware.gpu.enable;
        message = "hwc.server.jellyfin.gpu requires hwc.infrastructure.hardware.gpu.enable = true";
      }
    ];
  };
}