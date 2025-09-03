# nixos-hwc/modules/system/users.nix
#
# USERS - System domain user management and authentication
# Provides declarative user account configuration with agenix secret integration
#
# DEPENDENCIES (Upstream):
#   - agenix.nixosModules.default (flake.nix)
#   - age.secrets.* (modules/security/secrets.nix)
#
# USED BY (Downstream):
#   - profiles/*.nix (enables via hwc.system.users.enable)
#   - machines/*.nix (emergency access toggles)
#
# IMPORTS REQUIRED IN:
#   - profiles/base.nix: ../modules/system/users.nix
#
# USAGE:
#   hwc.system.users.enable = true;
#   hwc.system.users.user = "eric";
#   hwc.system.users.passwordSecret = "eric-password";

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.users;
in {
  #============================================================================
  # OPTIONS - User management configuration
  #============================================================================
  
  options.hwc.system.users = {
    enable = lib.mkEnableOption "system users management";
    
    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "Primary interactive user name";
    };
    
    description = lib.mkOption {
      type = lib.types.str;
      default = "Eric - Heartwood Craft";
      description = "User description";
    };
    
    shell = lib.mkOption {
      type = lib.types.package;
      default = pkgs.zsh;
      description = "Default shell for the user";
    };
    
    groups = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ "wheel" "networkmanager" "video" "input" "audio" "lp" "scanner" ];
      description = "Extra groups for the user";
    };
    
    passwordSecret = lib.mkOption {
      type = lib.types.str;
      default = "user-initial-password";
      description = "Agenix secret name providing hashed password";
    };
    
    emergencyEnable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable temporary emergency local password (use only during migrations)";
    };
    
    emergencyPassword = lib.mkOption {
      type = lib.types.str;
      default = "TempPass-DisableMeNow!";
      description = "Emergency password when emergencyEnable is true";
    };
    
    sshKeys = lib.mkOption {
      type = with lib.types; listOf str;
      default = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICubgcmg6aBisQC+MWRC4RWOY8zIHEl42O7bTbzyCiGB eriqueo@proton.me"
      ];
      description = "SSH public keys for the user";
    };
  };

  #============================================================================
  # IMPLEMENTATION - Declarative user configuration
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    # Validation assertions to prevent lockout
    assertions = [
      {
        assertion = config.age.secrets ? "${cfg.passwordSecret}" || cfg.emergencyEnable;
        message = "CRITICAL: No password secret '${cfg.passwordSecret}' found and emergency access disabled. This would lock you out! Enable emergencyEnable or ensure secret exists.";
      }
      {
        assertion = cfg.emergencyEnable -> (cfg.emergencyPassword != null && cfg.emergencyPassword != "");
        message = "CRITICAL: Emergency access enabled but no emergency password set.";
      }
    ];

    # Use declarative user management for security
    users.mutableUsers = false;

    # Primary user account configuration
    users.users."${cfg.user}" = {
      isNormalUser = true;
      description = cfg.description;
      shell = cfg.shell;
      extraGroups = cfg.groups;
      
      # SSH key configuration
      openssh.authorizedKeys.keys = cfg.sshKeys;
      
      # Password configuration with fallback chain
      # Priority: agenix secret → emergency password (if enabled)
      hashedPasswordFile = lib.mkIf (config.age.secrets ? "${cfg.passwordSecret}")
        config.age.secrets.${cfg.passwordSecret}.path;
      
      initialPassword = lib.mkIf cfg.emergencyEnable cfg.emergencyPassword;
    };

    # Warning when emergency access is enabled
    warnings = lib.optionals cfg.emergencyEnable [
      ''
        ##################################################################
        # SECURITY WARNING: EMERGENCY USER ACCESS IS ACTIVE              #
        # User '${cfg.user}' has emergency password enabled.             #
        # Disable hwc.system.users.emergencyEnable when finished.        #
        ##################################################################
      ''
    ];

    # Ensure ZSH is available system-wide
    programs.zsh.enable = lib.mkDefault true;
  };
}