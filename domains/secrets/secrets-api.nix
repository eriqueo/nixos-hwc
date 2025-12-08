# modules/security/materials.nix
#
# Stable materials facade - provides read-only path interface for consumers
# Isolates consumers from agenix internals and provides consistent access to secret paths
{ lib, config, ... }:

let
  # Helper function to get secret path or null if secret doesn't exist
  pathOrNull = name: 
    if config.age.secrets ? ${name} 
    then config.age.secrets.${name}.path 
    else null;
in
{
  #============================================================================

  #============================================================================
  # IMPLEMENTATION - Map secret names to their decrypted paths
  #============================================================================
  
  config.hwc.secrets.api = {
    # System domain paths
    userInitialPasswordFile = pathOrNull "user-initial-password";
    emergencyPasswordFile = pathOrNull "emergency-password";
    userSshPublicKeyFile = pathOrNull "user-ssh-public-key";
    
    # Services domain paths
    radarrApiKeyFile = pathOrNull "radarr-api-key";
    sonarrApiKeyFile = pathOrNull "sonarr-api-key";
    lidarrApiKeyFile = pathOrNull "lidarr-api-key";
    prowlarrApiKeyFile = pathOrNull "prowlarr-api-key";
    couchdbAdminUsernameFile = pathOrNull "couchdb-admin-username";
    couchdbAdminPasswordFile = pathOrNull "couchdb-admin-password";
    ntfyUserFile = pathOrNull "ntfy-user";
    navidromeAdminPasswordFile = pathOrNull "navidrome-admin-password";
    slackWebhookUrlFile = pathOrNull "slack-webhook-url";
    jellyfinApiKeyFile = pathOrNull "jellyfin-api-key";
    
    # Email domain paths
    protonBridgePasswordFile = pathOrNull "proton-bridge-password";
    gmailOauthClientFile = pathOrNull "gmail-oauth-client";

    
    # Infrastructure domain paths
    databaseNameFile = pathOrNull "database-name";
    databasePasswordFile = pathOrNull "database-password";
    databaseUserFile = pathOrNull "database-user";
    surveillanceRtspUsernameFile = pathOrNull "surveillance-rtsp-username";
    surveillanceRtspPasswordFile = pathOrNull "surveillance-rtsp-password";
    frigateRtspPasswordFile = pathOrNull "frigate-rtsp-password";
    
    # Networking domain paths
    vpnUsernameFile = pathOrNull "vpn-username";
    vpnPasswordFile = pathOrNull "vpn-password";
  };

  #============================================================================
  # VALIDATION - Ensure agenix is properly configured
  #============================================================================
  
  config = {
    # Warn if no identity paths configured
    warnings = lib.optionals (config.age.identityPaths or [] == []) [
      ''
        ##################################################################
        # AGENIX WARNING: No identity paths configured                  #
        # Secrets will not decrypt without age.identityPaths.           #
        # Ensure /etc/age/keys.txt exists or configure identity paths.  #
        ##################################################################
      ''
    ];
    
    # Assert critical secrets exist when needed
    assertions = [
      {
        assertion = config.hwc.secrets.api.userInitialPasswordFile != null 
                    || config.users.users.eric.initialHashedPassword or "" != "";
        message = ''
          CRITICAL: No user authentication configured. Either:
          - Ensure user-initial-password.age secret exists and is decryptable, OR  
          - Set users.users.eric.initialHashedPassword directly
          This prevents system lockout.
        '';
      }
    ];
  };
}
