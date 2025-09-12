# nixos-hwc/modules/system/security/sudo.nix
#
# SUDO - System security and privilege escalation management
# Provides centralized sudo configuration for system administration
#
# DEPENDENCIES (Upstream):
#   - users.users.* (modules/system/users.nix)
#
# USED BY (Downstream):
#   - profiles/*.nix (enables via hwc.system.security.sudo.enable)
#   - modules requiring admin privileges
#
# IMPORTS REQUIRED IN:
#   - profiles/base.nix: ../modules/system/security/sudo.nix
#
# USAGE:
#   hwc.system.security.sudo.enable = true;
#   hwc.system.security.sudo.wheelNeedsPassword = false;

{ config, lib, ... }:

let
  cfg = config.hwc.system.security.sudo;
in {
  #============================================================================
  # OPTIONS - Sudo security configuration
  #============================================================================
  
  options.hwc.system.security.sudo = {
    enable = lib.mkEnableOption "sudo privilege escalation configuration";
    
    wheelNeedsPassword = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether wheel group members need password for sudo";
    };
    
    enableExtraRules = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable custom sudo rules beyond wheel group";
    };
    
    extraUsers = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ "eric" ];
      description = "Users to grant additional sudo privileges";
    };
  };

  #============================================================================
  # IMPLEMENTATION - Sudo security configuration
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    # Core sudo configuration
    security.sudo = {
      enable = true;
      wheelNeedsPassword = cfg.wheelNeedsPassword;
      
      # Custom rules for specific users (optional)
      extraRules = lib.mkIf cfg.enableExtraRules [
        {
          users = cfg.extraUsers;
          commands = [
            {
              command = "ALL";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    };

    # Validation to ensure consistent configuration
    assertions = [
      {
        assertion = !cfg.enableExtraRules || (cfg.extraUsers != []);
        message = "Extra sudo rules enabled but no users specified in extraUsers";
      }
    ];

    # Warning when passwordless sudo is enabled
    warnings = lib.optionals (!cfg.wheelNeedsPassword || cfg.enableExtraRules) [
      ''
        ##################################################################
        # SECURITY NOTICE: PASSWORDLESS SUDO IS ACTIVE                   #
        # Current sudo configuration allows privilege escalation without  #
        # password prompts. This is convenient but reduces security.      #
        ##################################################################
      ''
    ];
  };
}