{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.jellyseerr;

  # Script to ensure all users have auto-approve permissions (222)
  updateUserPermissions = pkgs.writeShellScript "jellyseerr-update-permissions" ''
    DB_PATH="/opt/jellyseerr/config/db/db.sqlite3"

    # Wait for database to exist
    if [ -f "$DB_PATH" ]; then
      # Update all existing users to have auto-approve permissions (222)
      ${pkgs.sqlite}/bin/sqlite3 "$DB_PATH" \
        "UPDATE user SET permissions = 222 WHERE permissions != 222;" || true
    fi
  '';
in
{
  config = lib.mkIf cfg.enable {
    systemd.services."podman-jellyseerr".after = [ "network-online.target" "init-media-network.service" "agenix.service" ];
    systemd.services."podman-jellyseerr".wants  = [ "network-online.target" "agenix.service" ];

    # Ensure user permissions are set to auto-approve on every start
    systemd.services."podman-jellyseerr".preStart = ''
      ${updateUserPermissions}
    '';
  };
}
