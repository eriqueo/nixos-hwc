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
      # NOTE: migrations.xml pre-seeding removed (2026-02-13)
      # Jellyfin 10.11.x uses EF Core migrations stored in the database, not XML.
      # The old XML-based migrations.xml causes "Sequence contains no elements" crash.
      preStart = ''
        DATA_DIR="/var/lib/hwc/jellyfin/data"
        CONFIG_DIR="/var/lib/hwc/jellyfin/config"

        # Remove invalid database files that cause migration failures
        for db in activitylog.db displaypreferences.db authentication.db; do
          if [ -f "$DATA_DIR/$db" ]; then
            if [ ! -s "$DATA_DIR/$db" ]; then
              echo "Removing empty $db"
              rm -f "$DATA_DIR/$db"
            fi
          fi
        done

        # Remove old-style migrations.xml if present - incompatible with 10.11.x
        if [ -f "$CONFIG_DIR/migrations.xml" ]; then
          echo "Removing obsolete migrations.xml (incompatible with Jellyfin 10.11.x)"
          rm -f "$CONFIG_DIR/migrations.xml"
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

    # Ensure Jellyfin data/cache dirs are owned by eric (service runs as eric)
    systemd.tmpfiles.rules = [
      "d /var/lib/hwc/jellyfin 0750 eric users -"
      "d /var/lib/hwc/jellyfin/config 0750 eric users -"
      "d /var/lib/hwc/jellyfin/data 0750 eric users -"
      "d /var/lib/hwc/jellyfin/log 0750 eric users -"
      "d /var/cache/hwc/jellyfin 0750 eric users -"
    ];

    # Apply user policies via API after Jellyfin starts
    systemd.services.jellyfin-apply-policies = lib.mkIf (cfg.users != {} && cfg.apiKey != "") {
      description = "Apply Jellyfin user policies";
      after = [ "jellyfin.service" ];
      requires = [ "jellyfin.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = let
        applyUserPolicy = username: userCfg: ''
          echo "Applying policy for user: ${username}"

          # Get user ID
          USER_ID=$(${pkgs.curl}/bin/curl -sf "http://127.0.0.1:8096/Users" \
            -H "X-Emby-Token: ${cfg.apiKey}" | \
            ${pkgs.jq}/bin/jq -r '.[] | select(.Name == "${username}") | .Id')

          if [ -z "$USER_ID" ] || [ "$USER_ID" = "null" ]; then
            echo "User ${username} not found, skipping"
            return
          fi

          # Get current policy
          POLICY=$(${pkgs.curl}/bin/curl -sf "http://127.0.0.1:8096/Users/$USER_ID" \
            -H "X-Emby-Token: ${cfg.apiKey}" | \
            ${pkgs.jq}/bin/jq '.Policy')

          # Update MaxActiveSessions
          UPDATED_POLICY=$(echo "$POLICY" | ${pkgs.jq}/bin/jq '.MaxActiveSessions = ${toString userCfg.maxActiveSessions}')

          # Apply policy
          ${pkgs.curl}/bin/curl -sf -X POST "http://127.0.0.1:8096/Users/$USER_ID/Policy" \
            -H "X-Emby-Token: ${cfg.apiKey}" \
            -H "Content-Type: application/json" \
            -d "$UPDATED_POLICY"

          echo "Policy applied for ${username}"
        '';
      in ''
        # Wait for Jellyfin to be ready
        for i in $(seq 1 30); do
          if ${pkgs.curl}/bin/curl -sf "http://127.0.0.1:8096/System/Info" -H "X-Emby-Token: ${cfg.apiKey}" > /dev/null 2>&1; then
            break
          fi
          echo "Waiting for Jellyfin to be ready..."
          sleep 2
        done

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList applyUserPolicy cfg.users)}
      '';
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
