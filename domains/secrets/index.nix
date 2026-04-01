# domains/secrets/index.nix
#
# Secrets domain aggregator - single source of truth for all secrets
# Imports all secret declarations, API facade, emergency access, and hardening
{ lib, config, pkgs, ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.secrets = {
    # Master enable for secrets domain
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable secrets domain with secrets management";
    };

    #==========================================================================
    # API: Dynamic map of all declared agenix secrets → decrypted paths
    # Access: config.hwc.secrets.api."secret-name"
    # Populated automatically by secrets-api.nix from config.age.secrets.
    # No registration needed when adding new secrets.
    #==========================================================================
    api = lib.mkOption {
      type        = lib.types.attrsOf lib.types.path;
      default     = {};
      description = ''
        Map of agenix secret name → decrypted runtime path.
        Automatically populated from all declared age.secrets.
        Usage: config.hwc.secrets.api."my-secret-name"
        Use `config.hwc.secrets.api ? "my-secret-name"` to check existence.
      '';
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

  imports = [
    ./declarations/index.nix   # Age secret declarations organized by domain
    ./agenix-fix-argmax.nix    # Workaround: agenix inline script > 128KB limit
    ./emergency.nix            # Emergency root access for recovery
    ./hardening.nix            # Security hardening configuration
    ./vaultwarden/index.nix    # Vaultwarden password manager
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf config.hwc.secrets.enable {
    # Auto-populate secrets.api from all declared agenix secrets.
    # No registration needed — add a declaration and it appears here.
    hwc.secrets.api =
      builtins.mapAttrs (_: secret: secret.path) config.age.secrets;

    # Ensure age identity paths are configured
    age.identityPaths = lib.mkDefault [ "/etc/age/keys.txt" ];

    # Create age keys directory with proper permissions
    systemd.tmpfiles.rules = [
      "d /etc/age 0755 root root -"
    ];

    # Helper environment variable for easier secret directory access
    environment.sessionVariables = {
      HWC_SECRETS_DIR = "/run/agenix";
    };

    warnings =
      if (config.age.identityPaths or []) == [] then [
        ''
          ##################################################################
          # AGENIX WARNING: No identity paths configured                  #
          # Secrets will not decrypt without age.identityPaths.           #
          # Ensure /etc/age/keys.txt exists or configure identity paths.  #
          ##################################################################
        ''
      ] else [];

    assertions = [
      {
        assertion =
          config.hwc.secrets.api ? "user-initial-password"
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
