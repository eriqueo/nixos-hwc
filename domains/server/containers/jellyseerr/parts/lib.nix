{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.jellyseerr;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/jellyseerr/config";
  settings = import ./settings.nix { inherit config pkgs; };

  # Script to ensure all users have auto-approve permissions (222)
  updateUserPermissions = pkgs.writeShellScript "jellyseerr-update-permissions" ''
    DB_PATH="${configPath}/db/db.sqlite3"

    # Wait for database to exist
    if [ -f "$DB_PATH" ]; then
      # Update all existing users to have auto-approve permissions (222)
      ${pkgs.sqlite}/bin/sqlite3 "$DB_PATH" \
        "UPDATE user SET permissions = 222 WHERE permissions != 222;" || true
    fi
  '';

  ensureSettings = pkgs.writeShellScript "jellyseerr-ensure-settings" ''
    install -d -m 0755 -o 1000 -g 100 "${configPath}"
    install -m 0644 -o 1000 -g 100 "${settings.settingsFile}" "${configPath}/settings.json"
  '';
in
{
  config = lib.mkIf cfg.enable {
    systemd.services."podman-jellyseerr".after = [ "network-online.target" "init-media-network.service" "agenix.service" ];
    systemd.services."podman-jellyseerr".wants  = [ "network-online.target" "agenix.service" ];

    # Ensure user permissions are set to auto-approve on every start
    systemd.services."podman-jellyseerr".preStart = ''
      ${ensureSettings}
      ${updateUserPermissions}
    '';
  };
}
