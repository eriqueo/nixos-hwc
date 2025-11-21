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
      mkdir -p /mnt/hot/downloads/music
      mkdir -p /mnt/hot/downloads/torrents

      # Container config/data directories
      mkdir -p /opt/downloads/slskd
      mkdir -p /opt/downloads/soularr
      mkdir -p /opt/downloads/lidarr
      mkdir -p /opt/downloads/radarr
      mkdir -p /opt/downloads/sonarr
      mkdir -p /opt/downloads/prowlarr
      mkdir -p /opt/downloads/sabnzbd
      mkdir -p /opt/downloads/qbittorrent

      # slskd config directory (system-level)
      mkdir -p /etc/slskd
      mkdir -p /var/lib/slskd

      # Set ownership: eric:users for everything
      # You're the only user - no complex permissions needed
      chown -R eric:users /mnt/hot/downloads
      chown -R eric:users /opt/downloads
      chown -R root:root /etc/slskd
      chown -R root:root /var/lib/slskd

      # Set permissions: 0755 for directories (rwxr-xr-x)
      chmod -R 0755 /mnt/hot/downloads
      chmod -R 0755 /opt/downloads
      chmod -R 0755 /etc/slskd
      chmod -R 0755 /var/lib/slskd

      echo "Container directories created successfully"
    '';
  };
}
