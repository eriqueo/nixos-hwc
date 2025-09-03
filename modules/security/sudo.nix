# nixos-hwc/modules/security/sudo.nix
#
# SUDO CONFIGURATION - System privilege escalation management
# Charter v4 compliant sudo configuration separate from user definitions
#
# DEPENDENCIES (Upstream):
#   - modules/system/users.nix (provides user accounts)
#
# USED BY (Downstream):
#   - profiles/base.nix (enables via hwc.security.sudo.enable)
#   - profiles/workstation.nix (user-specific sudo rules)
#
# IMPORTS REQUIRED IN:
#   - profiles/base.nix: ../modules/security/sudo.nix
#
# USAGE:
#   hwc.security.sudo = {
#     enable = true;
#     wheelNeedsPassword = false;  # set true for production
#     extraRules = [ ... ];
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.security.sudo;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.security.sudo = {
    enable = lib.mkEnableOption "Sudo privilege escalation management";

    wheelNeedsPassword = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether wheel group users need password for sudo";
    };

    extraRules = lib.mkOption {
      type = with lib.types; listOf attrs;
      default = [];
      description = "Additional sudo rules beyond wheel group";
    };

    development = lib.mkOption {
      type = lib.types.bool; 
      default = true;
      description = "Enable development-friendly sudo settings (NOPASSWD for common commands)";
    };
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {
    # Enable sudo
    security.sudo.enable = true;
    
    # Configure wheel group password requirement
    security.sudo.wheelNeedsPassword = cfg.wheelNeedsPassword;
    
    # Development-friendly sudo rules
    security.sudo.extraRules = cfg.extraRules ++ lib.optionals cfg.development [
      {
        groups = [ "wheel" ];
        commands = [
          {
            command = "${pkgs.systemd}/bin/systemctl";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${pkgs.systemd}/bin/journalctl";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${pkgs.git}/bin/git";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${pkgs.nixos-rebuild}/bin/nixos-rebuild";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    # Security warnings for development mode
    warnings = lib.optionals cfg.development [
      ''
        DEVELOPMENT MODE: Sudo configured for development convenience with NOPASSWD
        for common system commands. Consider disabling hwc.security.sudo.development 
        in production environments.
      ''
    ];

    # Assertions for security
    assertions = [
      {
        assertion = config.hwc.system.users.enable or false;
        message = "hwc.security.sudo requires hwc.system.users to be enabled for proper user management";
      }
    ];
  };
}