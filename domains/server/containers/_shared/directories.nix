# Shared directory setup for all container services
# Creates all required directories with proper ownership BEFORE containers start
# Eliminates tmpfiles conflicts and unsafe path transition issues
{ lib, config, pkgs, ... }:

{
  # Single systemd service to set up ALL container directories
  # Runs once at boot, before any container services start
  systemd.services.container-directories-setup = {
    description = "Create all container download and data directories";
    wantedBy = [ "multi-user.target" ];
    before = [
      # Ensure this runs before ALL container services
      "podman-slskd.service"
      "podman-soularr.service"
      "podman-lidarr.service"
      "podman-radarr.service"
      "podman-sonarr.service"
      "podman-prowlarr.service"
      "podman-sabnzbd.service"
      "podman-qbittorrent.service"
    ];
    after = [ "local-fs.target" ];  # Wait for filesystems to be mounted
    wants = [ "local-fs.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      echo "Setting up container directories..."

      # Downloads structure (shared by multiple containers)
      mkdir -p /mnt/hot/downloads
      mkdir -p /mnt/hot/downloads/incomplete
      mkdir -p /mnt/hot/downloads/complete
      mkdir -p /mnt/hot/downloads/tv
      mkdir -p /mnt/hot/downloads/movies
      mkdir -p /mnt/hot/downloads/music

      # Event spool directory for media orchestration
      mkdir -p /mnt/hot/events

      # Processing directories for temporary operations
      mkdir -p /mnt/hot/processing/sonarr-temp
      mkdir -p /mnt/hot/processing/radarr-temp
      mkdir -p /mnt/hot/processing/lidarr-temp

      # Container config/data directories
      mkdir -p /opt/downloads/slskd
      mkdir -p /opt/downloads/soularr
      mkdir -p /opt/downloads/lidarr
      mkdir -p /opt/downloads/radarr
      mkdir -p /opt/downloads/sonarr
      mkdir -p /opt/downloads/prowlarr
      mkdir -p /opt/downloads/sabnzbd
      mkdir -p /opt/downloads/qbittorrent
      mkdir -p /opt/downloads/books

      # Books library directories
      mkdir -p /mnt/media/books/ebooks
      mkdir -p /mnt/media/books/audiobooks

      # Scripts directory for automation hooks
      mkdir -p /opt/downloads/scripts

      # slskd config directory (system-level)
      mkdir -p /etc/slskd
      mkdir -p /var/lib/slskd

      # COMPREHENSIVE PERMISSION ENFORCEMENT
      # ALL /mnt directories must be owned by eric:users for container access
      # Containers run as PUID=1000 (eric), PGID=100 (users)

      echo "Enforcing ownership on ALL /mnt directories..."
      chown -R eric:users /mnt/hot 2>/dev/null || true
      chown -R eric:users /mnt/media 2>/dev/null || true

      echo "Enforcing ownership on container data directories..."
      chown -R eric:users /opt/downloads 2>/dev/null || true
      chown -R root:root /etc/slskd 2>/dev/null || true
      chown -R root:root /var/lib/slskd 2>/dev/null || true

      echo "Setting directory permissions (0755) on ALL /mnt directories..."
      # Set permissions: 0755 for directories (rwxr-xr-x)
      # This allows eric to write, and containers (running as eric) to access
      find /mnt/hot -type d -exec chmod 0755 {} + 2>/dev/null || true
      find /mnt/media -type d -exec chmod 0755 {} + 2>/dev/null || true
      find /opt/downloads -type d -exec chmod 0755 {} + 2>/dev/null || true
      chmod -R 0755 /etc/slskd 2>/dev/null || true
      chmod -R 0755 /var/lib/slskd 2>/dev/null || true

      echo "Setting file permissions (0644) on ALL /mnt files..."
      # Set file permissions: 0644 for files (rw-r--r--)
      # This ensures downloaded files are readable by all but only writable by owner
      find /mnt/hot -type f -exec chmod 0644 {} + 2>/dev/null || true
      find /mnt/media -type f -exec chmod 0644 {} + 2>/dev/null || true

      # Scripts need to be executable
      find /opt/downloads/scripts -type f -name "*.sh" -exec chmod 0755 {} + 2>/dev/null || true
      find /opt/downloads/scripts -type f -name "*.py" -exec chmod 0755 {} + 2>/dev/null || true

      echo "Container directories created and permissions enforced successfully"
    '';
  };

  # NOTE: Hourly permission enforcement removed (2025-12-11)
  # Root cause fixed: containers now use correct PGID="100" (users group)
  # See docs/standards/permission-patterns.md for details
}
