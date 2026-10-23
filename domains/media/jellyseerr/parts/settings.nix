# domains/media/jellyseerr/parts/settings.nix
#
# Generates settings.json at RUNTIME (not evaluation time)
# to avoid pure evaluation errors with /run/agenix secrets

{ config, pkgs, ... }:
let
  defaultPermissions = 222;

  # Generate settings JSON at runtime using a script
  generateSettingsScript = pkgs.writeShellScript "jellyseerr-generate-settings" ''
    set -euo pipefail
    umask 077
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
        "defaultPermissions": ${toString defaultPermissions}
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
        "activeProfileId": 1,
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
        "activeProfileId": 1,
        "activeDirectory": "/tv",
        "activeAnimeProfileId": 1,
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
  inherit generateSettingsScript;
}
