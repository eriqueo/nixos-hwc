{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.jellyseerr;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/jellyseerr/config";
  settings = import ./settings.nix { inherit config pkgs; };

  # Add request/auto-approval without resetting owner, admin or custom grants.
  updateUserPermissions = pkgs.writeShellScript "jellyseerr-update-permissions" ''
    set -euo pipefail
    [ "$#" -eq 1 ] && [[ "$1" =~ ^[1-9][0-9]{0,9}$ ]] && [ "$1" -le 2147483647 ] || {
      echo "SEERR_PERMISSION_MASK_INVALID" >&2
      exit 1
    }
    DB_PATH="${configPath}/db/db.sqlite3"
    # First boot has no database yet; the app creates users with the safe default.
    if [ -f "$DB_PATH" ]; then
      ${pkgs.sqlite}/bin/sqlite3 -cmd '.timeout 5000' "$DB_PATH" \
        "UPDATE user SET permissions = permissions | $1 WHERE (permissions & $1) != $1;"
    fi
  '';

  ensureSettings = pkgs.writeShellScript "jellyseerr-ensure-settings" ''
    set -euo pipefail
    install -d -m 0700 -o 1000 -g 100 "${configPath}"
    ${settings.generateSettingsScript} "${configPath}/settings.json" "$1"
    chown 1000:100 "${configPath}/settings.json"
    chmod 0600 "${configPath}/settings.json"
  '';
in
{
  config = lib.mkIf cfg.enable {
    systemd.services."podman-jellyseerr".after = [ "network-online.target" "init-media-network.service" "agenix.service" ];
    systemd.services."podman-jellyseerr".wants  = [ "network-online.target" "agenix.service" ];

    system.build.seerrRequestPermissions = settings.requestPermissionsScript;
    system.build.seerrUserPermissions = updateUserPermissions;

    # Resolve one app-owned mask before either persistent settings or SQL writes.
    systemd.services."podman-jellyseerr".preStart = ''
      permissionMask=$(${settings.requestPermissionsScript})
      ${ensureSettings} "$permissionMask"
      ${updateUserPermissions} "$permissionMask"
    '';
  };
}
