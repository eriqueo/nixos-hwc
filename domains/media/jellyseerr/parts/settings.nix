# domains/media/jellyseerr/parts/settings.nix
#
# Generates settings.json at RUNTIME (not evaluation time)
# to avoid pure evaluation errors with /run/agenix secrets

{ config, pkgs, ... }:
let
  defaultPermissions = 222;

  # Generate settings JSON at runtime using a script
  generateSettingsScript = pkgs.writeShellScript "jellyseerr-generate-settings" ''
    JELLYFIN_KEY=$(cat ${config.hwc.secrets.api.jellyfinApiKeyFile} | tr -d '[:space:]')
    RADARR_KEY=$(cat ${config.hwc.secrets.api.radarrApiKeyFile} | tr -d '[:space:]')
    SONARR_KEY=$(cat ${config.hwc.secrets.api.sonarrApiKeyFile} | tr -d '[:space:]')

    cat > "$1" << EOF
    {
      "main": {
        "initialized": true,
        "trustProxy": true,
        "applicationUrl": "https://hwc.ocelot-wahoo.ts.net:5543",
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
        "hostname": "10.89.0.1",
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
        "hostname": "10.89.0.1",
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
  '';
in
{
  inherit generateSettingsScript;
}
