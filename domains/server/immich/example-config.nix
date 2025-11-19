# Example Immich Configuration for nixos-hwc
#
# This file demonstrates various configuration scenarios for Immich
# with optimal storage templates and backup integration.

{ config, lib, ... }:

{
  # ============================================================================
  # EXAMPLE 1: RECOMMENDED PRODUCTION SETUP
  # ============================================================================
  # This is the recommended configuration for most users.
  # It provides:
  # - Organized storage with separate directories
  # - Automatic backups of photos and database
  # - GPU acceleration for performance
  # - Redis caching

  hwc.server.immich = {
    enable = true;

    # Storage configuration with automatic directory creation
    storage = {
      enable = true;  # Default: true
      basePath = "/mnt/photos";

      # Default locations (can be customized):
      # locations = {
      #   library = "/mnt/photos/library";
      #   thumbs = "/mnt/photos/thumbs";
      #   encodedVideo = "/mnt/photos/encoded-video";
      #   profile = "/mnt/photos/profile";
      # };

      # Storage template documentation (configure via web UI):
      # Recommended: {{y}}/{{MM}}/{{dd}}/{{filename}}
      # Alternative: {{y}}/{{MM}}/{{album}}/{{filename}}
      # See STORAGE-GUIDE.md for all options
    };

    # Database configuration
    database = {
      name = "immich";
      user = "immich";
      createDB = false;  # Use existing PostgreSQL database
    };

    # Backup configuration (enabled by default)
    backup = {
      enable = true;
      includeDatabase = true;  # Daily database backups at 02:00
      databaseBackupPath = "/var/backup/immich-db";
      schedule = "daily";  # or "hourly" for more frequent backups
    };

    # Performance features
    redis.enable = true;  # Enable Redis caching for better performance
    gpu.enable = true;    # Enable GPU acceleration for ML and transcoding
  };

  # Add Immich paths to system backup (already configured in server config)
  # hwc.system.services.backup.local.sources = [
  #   "/mnt/photos"           # Immich media storage
  #   "/var/backup/immich-db" # Database backups
  # ];

  # ============================================================================
  # EXAMPLE 2: CUSTOM STORAGE PATHS
  # ============================================================================
  # Use this if you want to separate storage types across different drives
  # For example: thumbnails on SSD, videos on HDD

  # hwc.server.immich = {
  #   enable = true;
  #
  #   storage = {
  #     enable = true;
  #     basePath = "/mnt/photos";
  #
  #     locations = {
  #       library = "/mnt/photos/library";          # Main storage (HDD)
  #       thumbs = "/mnt/ssd-cache/immich-thumbs";  # Fast SSD for thumbnails
  #       encodedVideo = "/mnt/video-storage/immich"; # Separate video storage
  #       profile = "/mnt/photos/profile";
  #     };
  #   };
  #
  #   database.name = "immich";
  #   backup.enable = true;
  #   redis.enable = true;
  #   gpu.enable = true;
  # };
  #
  # # Update backup sources for custom paths
  # hwc.system.services.backup.local.sources = [
  #   "/mnt/photos/library"              # Primary photos
  #   "/mnt/photos/profile"              # Profile pictures
  #   "/mnt/video-storage/immich"        # Transcoded videos
  #   "/var/backup/immich-db"            # Database
  #   # Exclude: /mnt/ssd-cache/immich-thumbs (regenerable)
  # ];

  # ============================================================================
  # EXAMPLE 3: MINIMAL CONFIGURATION
  # ============================================================================
  # Simplest configuration using all defaults

  # hwc.server.immich = {
  #   enable = true;
  #   redis.enable = true;
  #   gpu.enable = true;
  # };
  #
  # This automatically configures:
  # - storage.basePath = "/mnt/photos"
  # - backup.enable = true (with database backups)
  # - Automatic directory creation
  # - All storage subdirectories

  # ============================================================================
  # EXAMPLE 4: HIGH-PERFORMANCE SETUP
  # ============================================================================
  # Optimized for performance with frequent backups

  # hwc.server.immich = {
  #   enable = true;
  #
  #   storage.enable = true;
  #   storage.basePath = "/mnt/photos";
  #
  #   database = {
  #     name = "immich";
  #     user = "immich";
  #     createDB = false;
  #   };
  #
  #   backup = {
  #     enable = true;
  #     includeDatabase = true;
  #     schedule = "hourly";  # More frequent database backups
  #   };
  #
  #   redis.enable = true;
  #   gpu.enable = true;
  #
  #   # Note: Adjust PostgreSQL settings for performance
  # };
  #
  # # Optimize PostgreSQL for Immich
  # services.postgresql = {
  #   settings = {
  #     shared_buffers = "256MB";
  #     effective_cache_size = "1GB";
  #     work_mem = "16MB";
  #     maintenance_work_mem = "128MB";
  #   };
  # };

  # ============================================================================
  # EXAMPLE 5: MULTI-USER FAMILY SETUP
  # ============================================================================
  # Configuration for multiple family members
  # Each user gets their own namespace automatically

  # hwc.server.immich = {
  #   enable = true;
  #
  #   storage = {
  #     enable = true;
  #     basePath = "/mnt/photos";
  #     # Storage template (configure via web UI):
  #     # {{y}}/{{MM}}/{{album}}/{{filename}}
  #     # This organizes photos by year/month/album
  #   };
  #
  #   database.name = "immich";
  #
  #   backup = {
  #     enable = true;
  #     includeDatabase = true;
  #     schedule = "daily";
  #   };
  #
  #   redis.enable = true;
  #   gpu.enable = true;
  # };
  #
  # # Users are managed through Immich web UI:
  # # 1. Admin creates user accounts
  # # 2. Each user uploads to their own library
  # # 3. Storage template applies per-user
  # # 4. Users can share albums with each other

  # ============================================================================
  # STORAGE TEMPLATE CONFIGURATION (WEB UI)
  # ============================================================================
  # Storage templates are configured via Immich web UI:
  #
  # 1. Log in as admin: https://hwc.ocelot-wahoo.ts.net:7443
  # 2. Navigate to: Administration → Settings → Storage Template
  # 3. Configure template using variables:
  #
  # Recommended Templates:
  #
  # A. Date-based (Best for most users):
  #    {{y}}/{{MM}}/{{dd}}/{{filename}}
  #    Result: 2025/01/15/IMG_20250115_120000.jpg
  #
  # B. Monthly organization:
  #    {{y}}/{{MM}}/{{filename}}
  #    Result: 2025/01/IMG_20250115_120000.jpg
  #
  # C. Album-based:
  #    {{y}}/{{MM}}/{{album}}/{{filename}}
  #    Result: 2025/01/Vacation/IMG_20250115_120000.jpg
  #
  # D. Camera/device-based:
  #    {{y}}/{{MM}}/{{assetId}}/{{filename}}
  #    Result: 2025/01/abc123.../IMG_20250115_120000.jpg
  #
  # Available variables:
  # - {{y}}, {{yy}} - Year (4 or 2 digits)
  # - {{MM}}, {{MMM}} - Month (number or name)
  # - {{dd}} - Day
  # - {{hh}}, {{mm}}, {{ss}} - Hour, minute, second
  # - {{filename}} - Original filename
  # - {{ext}} - File extension
  # - {{album}} - Album name
  # - {{assetId}} - Immich asset ID
  #
  # See STORAGE-GUIDE.md for detailed instructions.

  # ============================================================================
  # BACKUP VERIFICATION
  # ============================================================================
  # Commands to verify backup configuration:
  #
  # Check database backups:
  #   ls -lh /var/backup/immich-db/
  #
  # Check backup service status:
  #   systemctl status postgresqlBackup-immich.service
  #
  # View backup logs:
  #   journalctl -u postgresqlBackup-immich.service -n 50
  #
  # Manually trigger database backup:
  #   sudo systemctl start postgresqlBackup-immich.service
  #
  # Check photo backup sources:
  #   # Verify /mnt/photos is in backup sources
  #   nixos-option hwc.system.services.backup.local.sources

  # ============================================================================
  # MIGRATION FROM OLD STORAGE LAYOUT
  # ============================================================================
  # If you have existing Immich data:
  #
  # 1. BACKUP FIRST:
  #    sudo rsync -av /mnt/photos/ /mnt/backup/immich-pre-migration/
  #
  # 2. Deploy new configuration:
  #    sudo nixos-rebuild switch
  #
  # 3. Configure storage template via web UI
  #
  # 4. Run storage migration job:
  #    Administration → Jobs → Storage Migration Jobs → Run Job
  #
  # See STORAGE-GUIDE.md for detailed migration instructions.
}
