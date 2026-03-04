# domains/server/containers/audiobookshelf/parts/config.nix
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.audiobookshelf;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/audiobookshelf/config";

  # Script to ensure audiobookshelf directories exist with correct permissions
  ensureConfig = pkgs.writeShellScript "ensure-audiobookshelf-config" ''
    set -euo pipefail

    CONFIG_DIR="${configPath}"
    LIBRARY_DIR="${cfg.library}"
    PODCASTS_DIR="${cfg.podcasts}"
    METADATA_DIR="${cfg.metadata}"

    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    chown 1000:100 "$CONFIG_DIR"

    # Ensure library directories exist
    mkdir -p "$LIBRARY_DIR"
    mkdir -p "$PODCASTS_DIR"
    mkdir -p "$METADATA_DIR"
    chown -R 1000:100 "$LIBRARY_DIR" "$PODCASTS_DIR" "$METADATA_DIR"
  '';
in
{
  config = lib.mkIf cfg.enable {
    # Systemd service dependencies for audiobookshelf container
    systemd.services."podman-audiobookshelf" = {
      serviceConfig.ExecStartPre = [
        "+${ensureConfig}"
      ];
      after = [
        "network-online.target"
        "init-media-network.service"
        "agenix.service"
        "mnt-media.mount"
      ];
      wants = [
        "network-online.target"
        "agenix.service"
      ];
      requires = [ "mnt-media.mount" ];
    };
  };
}
