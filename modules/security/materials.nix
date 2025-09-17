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
  # OPTIONS - Stable read-only path interface for consumers
  #============================================================================
  
  options.hwc.security.materials = {
    # System domain secret paths
    userInitialPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted user initial password file";
    };
    
    emergencyPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted emergency password file";
    };
    
    userSshPublicKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted user SSH public key file";
    };
    
    # Services domain secret paths
    radarrApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted Radarr API key file";
    };
    
    sonarrApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted Sonarr API key file";
    };
    
    lidarrApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted Lidarr API key file";
    };
    
    prowlarrApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted Prowlarr API key file";
    };
    
    couchdbAdminUsernameFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted CouchDB admin username file";
    };
    
    couchdbAdminPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted CouchDB admin password file";
    };
    
    ntfyUserFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted NTFY user credentials file";
    };
    
    # Email domain secret paths
    protonBridgePasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted ProtonMail Bridge password file";
    };
    
    # Infrastructure domain secret paths
    databaseNameFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted database name file";
    };
    
    databasePasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted database password file";
    };
    
    databaseUserFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted database user file";
    };
    
    surveillanceRtspUsernameFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted surveillance RTSP username file";
    };
    
    surveillanceRtspPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted surveillance RTSP password file";
    };
    
    frigateRtspPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted Frigate RTSP password file";
    };
    
    # Networking domain secret paths
    vpnUsernameFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted VPN username file";
    };
    
    vpnPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Path to decrypted VPN password file";
    };
  };

  #============================================================================
  # IMPLEMENTATION - Map secret names to their decrypted paths
  #============================================================================
  
  config.hwc.security.materials = {
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
    
    # Email domain paths
    protonBridgePasswordFile = pathOrNull "proton-bridge-password";
    
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
        assertion = config.hwc.security.materials.userInitialPasswordFile != null 
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