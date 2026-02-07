{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.native.jellyfin;

  # Custom ffmpeg with NVENC/CUDA support for GPU transcoding
  ffmpeg-nvenc = pkgs.ffmpeg-full.override {
    withUnfree = true;
    withCuda   = true;
    withNvenc  = true;
  };

  # User initialization script
  initUsersScript = import ./parts/init-users.nix { inherit pkgs config; };
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
      dataDir = "/var/lib/hwc/jellyfin";  # Override default /var/lib/jellyfin
      cacheDir = "/var/cache/hwc/jellyfin";  # Override default /var/cache/jellyfin
      package = pkgs.jellyfin.override {
        jellyfin-ffmpeg = ffmpeg-nvenc;
      };
    };



    # Manual firewall configuration (matching /etc/nixos pattern)
    networking.firewall = lib.mkIf (!cfg.openFirewall) {
      allowedTCPPorts = [ 8096 7359 ];  # HTTP + TCP discovery
      allowedUDPPorts = [ 7359 ];       # UDP discovery
    };

    # GPU acceleration and migration fix configuration
    systemd.services.jellyfin = {
      # Fix corrupted migration files and initialize users before startup
      preStart = ''
        CONFIG_DIR="/var/lib/hwc/jellyfin/config"

        # Remove corrupted migrations.xml that causes "Sequence contains no elements" crash
        # Jellyfin will regenerate this file on startup with correct format for 10.11+
        if [ -f "$CONFIG_DIR/migrations.xml" ]; then
          if grep -q "CreateNetworkConfiguration" "$CONFIG_DIR/migrations.xml" 2>/dev/null; then
            echo "Removing old-format migrations.xml (pre-10.11 format incompatible)"
            rm -f "$CONFIG_DIR/migrations.xml"
          fi
        fi

        # Initialize users before Jellyfin starts
        echo "Initializing Jellyfin users..."
        ${initUsersScript}
      '';

      serviceConfig = {
        # Run as eric user for simplified permissions (single-user system)
        User = lib.mkForce "eric";
        Group = lib.mkForce "users";

        # Override state/cache directories
        StateDirectory = lib.mkForce "hwc/jellyfin";
        CacheDirectory = lib.mkForce "hwc/jellyfin";

        # Relax isolation enough to see GPU device nodes
        PrivateUsers = lib.mkForce false;
        PrivateDevices = lib.mkForce false;
        DevicePolicy = lib.mkForce "auto";

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

      environment = lib.mkIf cfg.gpu.enable {
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
        assertion = !cfg.reverseProxy.enable || config.hwc.server.reverseProxy.enable;
        message = "hwc.server.jellyfin.reverseProxy requires hwc.server.reverseProxy.enable = true";
      }
      {
        assertion = !cfg.gpu.enable || config.hwc.infrastructure.hardware.gpu.enable;
        message = "hwc.server.jellyfin.gpu requires hwc.infrastructure.hardware.gpu.enable = true";
      }
      {
        assertion = cfg.enable -> (config.age.secrets ? jellyfin-admin-password && config.age.secrets ? jellyfin-eric-password);
        message = "hwc.server.jellyfin requires jellyfin-admin-password and jellyfin-eric-password secrets to be defined";
      }
    ];
  };
}
