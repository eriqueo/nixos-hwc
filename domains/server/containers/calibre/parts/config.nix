{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.calibre;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/calibre/config";

  # Script to ensure calibre config directory exists with correct permissions
  ensureConfig = pkgs.writeShellScript "ensure-calibre-config" ''
    set -euo pipefail

    CONFIG_DIR="${configPath}"
    LIBRARY_DIR="${cfg.library}"

    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    chown 1000:100 "$CONFIG_DIR"

    # Ensure library directory exists
    mkdir -p "$LIBRARY_DIR"
    chown -R 1000:100 "$LIBRARY_DIR"
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
