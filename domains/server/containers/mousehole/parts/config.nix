# domains/server/containers/mousehole/parts/config.nix
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.mousehole;
  appsRoot = config.hwc.paths.apps.root;
  dataPath = "${appsRoot}/mousehole/data";

  # Script to ensure mousehole data directory exists
  ensureConfig = pkgs.writeShellScript "ensure-mousehole-config" ''
    set -euo pipefail

    DATA_DIR="${dataPath}"

    # Create data directory if it doesn't exist
    mkdir -p "$DATA_DIR"
    chown 1000:100 "$DATA_DIR"
  '';
in
{
  config = lib.mkIf cfg.enable {
    # Systemd service dependencies for mousehole container
    systemd.services."podman-mousehole" = {
      serviceConfig.ExecStartPre = [
        "+${ensureConfig}"
      ];
      after = [
        "podman-gluetun.service"
      ];
      requires = [ "podman-gluetun.service" ];
    };
  };
}
