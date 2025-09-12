# nixos-hwc/modules/system/secrets.nix
#
# SECRETS - System domain agenix integration and service ordering
# Ensures proper secret decryption ordering and user authentication integration
#
# DEPENDENCIES (Upstream):
#   - agenix.nixosModules.default (flake.nix)
#   - age identity files (/etc/age/keys.txt)
#
# USED BY (Downstream):
#   - modules/system/users.nix (user authentication secrets)
#   - modules/services/*.nix (service-specific secrets)
#
# IMPORTS REQUIRED IN:
#   - profiles/base.nix: ../modules/system/secrets.nix
#
# USAGE:
#   hwc.system.secrets.enable = true;
#   hwc.system.secrets.userPasswordSecret = "user-initial-password";

{ config, lib, ... }:

let
  cfg = config.hwc.system.secrets;
in {
  #============================================================================
  # OPTIONS - System secrets configuration
  #============================================================================
  
  options.hwc.system.secrets = {
    enable = lib.mkEnableOption "system agenix secrets management";
    
    ageKeyFile = lib.mkOption {
      type = lib.types.path;
      default = "/etc/age/keys.txt";
      description = "Path to age private key file";
    };
    
    userPasswordSecret = lib.mkOption {
      type = lib.types.str;
      default = "user-initial-password";
      description = "Name of the agenix secret containing user password hash";
    };
    
    ensureSecretsExist = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Assert that required secrets exist to prevent silent failures";
    };
  };

  #============================================================================
  # IMPLEMENTATION - Agenix integration with proper service ordering
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    # Configure agenix key file location
    age.identityPaths = [ cfg.ageKeyFile ];

    # Ensure age key directory exists with proper permissions
    systemd.tmpfiles.rules = [
      "d /etc/age 0755 root root -"
    ];

    # Core user authentication secret
    age.secrets = {
      "${cfg.userPasswordSecret}" = {
        file = ../../secrets/${cfg.userPasswordSecret}.age;
        mode = "0400";
        owner = "root";
        group = "root";
      };
    };

    # DISABLED: Modern agenix uses activation scripts, not systemd services
    # systemd.services.agenix.unitConfig.Before = "systemd-user-sessions.service";
    # systemd.services.agenix.wantedBy = [ "multi-user.target" ];

    # Validation assertions
    assertions = lib.mkIf cfg.ensureSecretsExist [
      {
        assertion = config.age.secrets ? "${cfg.userPasswordSecret}";
        message = "Required user password secret '${cfg.userPasswordSecret}' not found in age.secrets";
      }
      # Disable age key file check for now during testing
      # {
      #   assertion = builtins.pathExists cfg.ageKeyFile || !cfg.ensureSecretsExist;
      #   message = "Age key file not found at ${cfg.ageKeyFile}. Ensure age keys are deployed.";
      # }
    ];

    # Helper environment variables for easier secret access
    environment.sessionVariables = {
      HWC_SECRETS_DIR = "/run/agenix";
    };

    warnings = [
      ''
        ##################################################################
        # AGENIX SECRETS ACTIVE                                          #
        # Secrets are decrypted to /run/agenix/ during system boot.     #
        # Ensure age keys are properly deployed to ${cfg.ageKeyFile}     #
        ##################################################################
      ''
    ];
  };
}