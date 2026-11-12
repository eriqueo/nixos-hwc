# domains/media/jellyseerr/parts/settings.nix
#
# Generates settings.json at RUNTIME (not evaluation time)
# to avoid pure evaluation errors with /run/agenix secrets

{ config, pkgs, ... }:
let
  # The configured app owns the bit vocabulary. Run only its pure enum module,
  # without config mounts, network, write access or inherited privileges.
  requestPermissionsScript = pkgs.writeShellScript "jellyseerr-request-permissions" ''
    set -euo pipefail
    exec ${pkgs.podman}/bin/podman run --rm --pull=never --network=none \
      --user=1000:100 --cap-drop=all --security-opt=no-new-privileges \
      --read-only --memory=128m --cpus=1 --pids-limit=64 --timeout=15 \
      --entrypoint=/usr/local/bin/node \
      ${pkgs.lib.escapeShellArg config.hwc.media.jellyseerr.image} -e '
        const { Permission } = require("/app/dist/lib/permissions.js");
        const bit = value => Number.isInteger(value) && value > 0 &&
          value <= 0x40000000 && (value & (value - 1)) === 0;
        if (![Permission.REQUEST, Permission.AUTO_APPROVE, Permission.ADMIN].every(bit) ||
            Permission.REQUEST === Permission.AUTO_APPROVE) {
          throw new Error("SEERR_PERMISSION_ENUM_INVALID");
        }
        const mask = Permission.REQUEST | Permission.AUTO_APPROVE;
        const forbidden = Object.entries(Permission)
          .filter(([name]) => name === "ADMIN" || name.startsWith("MANAGE_"));
        if (forbidden.some(([, value]) => !bit(value) || (mask & value) !== 0)) {
          throw new Error("SEERR_REQUEST_PERMISSION_HAS_MANAGEMENT_AUTHORITY");
        }
        process.stdout.write(String(mask) + "\n");
      '
  '';

  # Generate settings JSON at runtime using a script
  generateSettingsScript = pkgs.writeShellScript "jellyseerr-generate-settings" ''
    set -euo pipefail
    umask 077
    [ "$#" -eq 2 ] && [[ "$2" =~ ^[1-9][0-9]{0,9}$ ]] && [ "$2" -le 2147483647 ] || {
      echo "SEERR_PERMISSION_MASK_INVALID" >&2
      exit 1
    }
    permissionMask="$2"
    JELLYFIN_KEY=$(cat ${config.hwc.secrets.api."jellyfin-api-key"} | tr -d '[:space:]')
    RADARR_KEY=$(cat ${config.hwc.secrets.api."radarr-api-key"} | tr -d '[:space:]')
    SONARR_KEY=$(cat ${config.hwc.secrets.api."sonarr-api-key"} | tr -d '[:space:]')

    [ -n "$JELLYFIN_KEY" ] && [ -n "$RADARR_KEY" ] && [ -n "$SONARR_KEY" ] || {
      echo "Seerr requires nonempty integration keys" >&2
      exit 1
    }
    target="$1"
    desired=""
    merged=""
    trap 'rm -f -- "$desired" "$merged"' EXIT
    desired=$(mktemp "$target.declarative.XXXXXX")
    merged=$(mktemp "$target.merged.XXXXXX")
    cat > "$desired" << EOF
    {
      "main": {
        "initialized": true,
        "trustProxy": true,
        "applicationUrl": "https://jellyseerr.hwc.iheartwoodcraft.com",
        "mediaServerType": 2,
        "mediaServerLogin": true,
        "localLogin": false,
        "defaultPermissions": $permissionMask
      },
      "public": {
        "initialized": true,
        "localLogin": false,
        "mediaServerLogin": true
      },
      "auth": {
        "local": { "enabled": false },
        "jellyfin": { "enabled": true }
      },
      "jellyfin": {
        "ip": "10.89.0.1",
        "port": 8096,
        "useSsl": false,
        "urlBase": "",
        "externalHostname": "",
        "serverId": "016e351828c841fb83af163a59198649",
        "apiKey": "$JELLYFIN_KEY"
      },
      "radarr": [{
        "id": 0,
        "name": "Radarr",
        "hostname": "radarr",
        "port": 7878,
        "apiKey": "$RADARR_KEY",
        "useSsl": false,
        "activeProfileId": 7,
        "activeDirectory": "/movies",
        "is4k": false,
        "isDefault": true,
        "externalUrl": "",
        "syncEnabled": false,
        "preventSearch": false
      }],
      "sonarr": [{
        "id": 0,
        "name": "Sonarr",
        "hostname": "sonarr",
        "port": 8989,
        "apiKey": "$SONARR_KEY",
        "useSsl": false,
        "activeProfileId": 8,
        "activeDirectory": "/tv",
        "activeAnimeProfileId": 8,
        "activeAnimeDirectory": "/tv",
        "is4k": false,
        "isDefault": true,
        "enableSeasonFolders": true,
        "externalUrl": "",
        "syncEnabled": false,
        "preventSearch": false
      }]
    }
    EOF
    if [ -e "$target" ] || [ -L "$target" ]; then
      [ -f "$target" ] || { echo "Seerr settings must be a regular file" >&2; exit 1; }
      ${pkgs.jq}/bin/jq -e 'type == "object"' "$target" >/dev/null
      # Nix owns declared values and server membership; Seerr owns identities,
      # library selection and unknown fields on each matching server ID.
      ${pkgs.jq}/bin/jq -e -s '
        def servers($old; $wanted):
          [$wanted[] | . as $owned |
            (($old // [] | map(select(.id == $owned.id)) | .[0]) // {}) * $owned];
        .[0] as $old | .[1] as $wanted |
        ($old * $wanted) |
        .radarr = servers($old.radarr; $wanted.radarr) |
        .sonarr = servers($old.sonarr; $wanted.sonarr)
      ' "$target" "$desired" > "$merged"
    else
      ${pkgs.jq}/bin/jq -e 'select(type == "object")' "$desired" > "$merged"
    fi
    mv -f -- "$merged" "$target"
  '';
in
{
  inherit generateSettingsScript requestPermissionsScript;
}
