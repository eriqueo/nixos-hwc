{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.calibre;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/calibre/config";

  # Script to ensure calibre config directory exists with correct permissions
  ensureConfig = pkgs.writeShellScript "ensure-calibre-config" ''
    set -euo pipefail

    CONFIG_DIR="${configPath}"
    EBOOKS_DIR="${cfg.libraries.ebooks}"
    AUDIOBOOKS_DIR="${cfg.libraries.audiobooks}"

    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    chown 1000:100 "$CONFIG_DIR"

    # Ensure library directories exist
    mkdir -p "$EBOOKS_DIR"
    mkdir -p "$AUDIOBOOKS_DIR"
    chown -R 1000:100 "$EBOOKS_DIR" "$AUDIOBOOKS_DIR"
  '';
in
{
  config = lib.mkIf cfg.enable {
    # Systemd service dependencies for calibre container
    systemd.services."podman-calibre" = {
      serviceConfig.ExecStartPre = [
        "+${ensureConfig}"
      ];
      after = [
        "network-online.target"
        "init-media-network.service"
        "agenix.service"
        "mnt-hot.mount"
        "mnt-media.mount"
      ];
      wants = [
        "network-online.target"
        "agenix.service"
      ];
      requires = [ "mnt-hot.mount" "mnt-media.mount" ];
    };
  };
}
