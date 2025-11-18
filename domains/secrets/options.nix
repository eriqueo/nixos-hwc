# domains/secrets/options.nix
#
# Consolidated options for secrets domain
# Charter-compliant: ALL options defined here, implementations in separate files

{ lib, ... }:

{
  options.hwc.secrets = {
    # Master enable for secrets domain
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable secrets domain with secrets management";
    };

    #==========================================================================
    # API: Stable paths to decrypted secrets
    #==========================================================================
    api = {
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

      # Server domain secret paths
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

      geminiApiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        readOnly = true;
        description = "Path to decrypted Gemini API key file";
      };

      # Home domain secret paths (email)
      protonBridgePasswordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        readOnly = true;
        description = "Path to decrypted ProtonMail Bridge password file";
      };

      gmailPersonalPasswordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        readOnly = true;
        description = "Path to decrypted Gmail personal password file";
      };

      gmailBusinessPasswordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        readOnly = true;
        description = "Path to decrypted Gmail business password file";
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
      gmailOauthClientFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        readOnly = true;
        description = "Path to decrypted Gmail OAuth client JSON file";
      };

    };

    #==========================================================================
    # EMERGENCY: Break-glass root access
    #==========================================================================
    emergency = {
      enable = lib.mkEnableOption "Emergency root password access (temporary)";

      # Plaintext (discouraged; becomes initialPassword)
      password = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "PLAINTEXT emergency password (applied as initialPassword). Prefer hashed/passwordFile.";
      };

      # Plaintext file (good with agenix: config.age.secrets.<name>.path)
      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to PLAINTEXT password file (e.g. agenix secret path).";
      };

      # Hashed inputs (preferred)
      hashedPassword = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Hashed password (e.g. mkpasswd -m sha-512). Preferred.";
      };

      hashedPasswordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing a hashed password. Preferred.";
      };
    };

    #==========================================================================
    # HARDENING: Security hardening configuration
    #==========================================================================
    hardening = {
      enable = lib.mkEnableOption "Security hardening";

      firewall = {
        strictMode = lib.mkEnableOption "Strict firewall mode";

        allowedServices = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "ssh" "http" "https" ];
          description = "Allowed services";
        };

        trustedInterfaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "lo" ];
          description = "Trusted network interfaces";
        };
      };

      fail2ban = {
        enable = lib.mkEnableOption "Fail2ban intrusion prevention";

        maxRetries = lib.mkOption {
          type = lib.types.int;
          default = 5;
          description = "Max failed attempts";
        };

        banTime = lib.mkOption {
          type = lib.types.str;
          default = "10m";
          description = "Ban duration";
        };
      };

      ssh = {
        passwordAuthentication = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Allow password auth";
        };

        permitRootLogin = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Allow root SSH";
        };
      };

      audit = {
        enable = lib.mkEnableOption "Security auditing";

        rules = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Audit rules";
        };
      };
    };
  };
}
