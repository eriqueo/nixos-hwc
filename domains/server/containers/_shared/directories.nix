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

      # Set ownership: eric:users for download directories
      # Containers run as eric's UID, so they need write access
      chown -R eric:users /mnt/hot/downloads
      chown -R eric:users /mnt/hot/events
      chown -R eric:users /mnt/hot/processing
      chown -R eric:users /opt/downloads
      chown -R root:root /etc/slskd
      chown -R root:root /var/lib/slskd

      # Set permissions: 0755 for directories (rwxr-xr-x)
      # This allows eric to write, and containers (running as eric) to access
      find /mnt/hot/downloads -type d -exec chmod 0755 {} +
      find /mnt/hot/events -type d -exec chmod 0755 {} +
      find /mnt/hot/processing -type d -exec chmod 0755 {} +
      find /opt/downloads -type d -exec chmod 0755 {} +
      chmod -R 0755 /etc/slskd
      chmod -R 0755 /var/lib/slskd

      # Set file permissions: 0644 for files (rw-r--r--)
      # This ensures downloaded files are readable by all but only writable by owner
      find /mnt/hot/downloads -type f -exec chmod 0644 {} + 2>/dev/null || true
      find /opt/downloads/scripts -type f -name "*.sh" -exec chmod 0755 {} + 2>/dev/null || true
      find /opt/downloads/scripts -type f -name "*.py" -exec chmod 0755 {} + 2>/dev/null || true

      echo "Container directories created successfully with proper permissions"
    '';
  };
}
