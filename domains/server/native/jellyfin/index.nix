{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.native.jellyfin;

  # Custom ffmpeg with NVENC/CUDA support for GPU transcoding
  ffmpeg-nvenc = pkgs.ffmpeg-full.override {
    withUnfree = true;
    withCuda   = true;
    withNvenc  = true;
  };

  # NOTE: User initialization script removed (2026-02-08)
  # The init-users.nix script is incompatible with Jellyfin 10.9.11+ EF Core migrations.
  # Users should be created through the Jellyfin web UI wizard on first boot.
  # The old script wrote to the legacy SQLite Users table, but Jellyfin 10.9.11
  # expects users in EF Core format with migrations from LocalUsersv2.
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
      # Fix migration issues before startup
      # Jellyfin 10.9.11+ has migration routines that fail on fresh installs
      # because they expect old database tables that don't exist.
      preStart = ''
        DATA_DIR="/var/lib/hwc/jellyfin/data"
        CONFIG_DIR="/var/lib/hwc/jellyfin/config"
        MIGRATIONS_FILE="$CONFIG_DIR/migrations.xml"

        # Remove invalid database files that cause migration failures
        for db in activitylog.db displaypreferences.db authentication.db; do
          if [ -f "$DATA_DIR/$db" ]; then
            if [ ! -s "$DATA_DIR/$db" ]; then
              echo "Removing empty $db"
              rm -f "$DATA_DIR/$db"
            fi
          fi
        done

        # Pre-seed migrations.xml with problematic migrations marked as complete
        # These migrations fail on fresh installs because they expect old database tables
        if [ ! -f "$MIGRATIONS_FILE" ]; then
          echo "Creating migrations.xml with pre-seeded migrations..."
          cat > "$MIGRATIONS_FILE" << 'MIGRATIONS_EOF'
<?xml version="1.0" encoding="utf-8"?>
<MigrationOptions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <Applied>
    <ValueTupleOfGuidString>
      <Item1>9b354818-94d5-4b68-ac49-e35cb85f9d84</Item1>
      <Item2>CreateNetworkConfiguration</Item2>
    </ValueTupleOfGuidString>
    <ValueTupleOfGuidString>
      <Item1>a6dcacf4-c057-4ef9-80d3-61cef9ddb4f0</Item1>
      <Item2>MigrateMusicBrainzTimeout</Item2>
    </ValueTupleOfGuidString>
    <ValueTupleOfGuidString>
      <Item1>4fb5c950-1991-11ee-9b4b-0800200c9a66</Item1>
      <Item2>MigrateNetworkConfiguration</Item2>
    </ValueTupleOfGuidString>
    <ValueTupleOfGuidString>
      <Item1>4124c2cd-e939-4ffb-9be9-9b311c413638</Item1>
      <Item2>DisableTranscodingThrottling</Item2>
    </ValueTupleOfGuidString>
    <ValueTupleOfGuidString>
      <Item1>ef103419-8451-40d8-9f34-d1a8e93a1679</Item1>
      <Item2>CreateLoggingConfigHeirarchy</Item2>
    </ValueTupleOfGuidString>
    <ValueTupleOfGuidString>
      <Item1>3793eb59-bc8c-456c-8b9f-bd5a62a42978</Item1>
      <Item2>MigrateActivityLogDatabase</Item2>
    </ValueTupleOfGuidString>
    <ValueTupleOfGuidString>
      <Item1>5c4b82a2-f053-4009-bd05-b6fcad82f14c</Item1>
      <Item2>MigrateUserDatabase</Item2>
    </ValueTupleOfGuidString>
    <ValueTupleOfGuidString>
      <Item1>06387815-c3cc-421f-a888-fb5f9992bea8</Item1>
      <Item2>MigrateDisplayPreferencesDatabase</Item2>
    </ValueTupleOfGuidString>
    <ValueTupleOfGuidString>
      <Item1>5bd72f41-e6f3-4f60-90aa-09869abe0e22</Item1>
      <Item2>MigrateAuthenticationDatabase</Item2>
    </ValueTupleOfGuidString>
  </Applied>
</MigrationOptions>
MIGRATIONS_EOF
        fi
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
      # NOTE: Secret assertions removed (2026-02-08)
      # User initialization via secrets is incompatible with Jellyfin 10.9.11+ EF Core.
      # Users should be created through the web UI wizard instead.
    ];
  };
}
