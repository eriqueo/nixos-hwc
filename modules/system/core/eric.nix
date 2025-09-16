# nixos-hwc/modules/system/eric.nix
#
# ERIC USER MANAGEMENT - Complete user configuration for single-user system
# Defines user account, groups, environment, and SSH access for eric user
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.* (modules/system/paths.nix)
#   - config.hwc.security.materials.* (modules/security/ domain)
#
# USED BY (Downstream):
#   - profiles/base.nix (enables via hwc.system.users options)
#   - profiles/workstation.nix (user environment configuration)
#
# IMPORTS REQUIRED IN:
#   - profiles/base.nix: ../modules/system/eric.nix
#
# USAGE:
#   hwc.system.users.enable = true;              # Enable user management
#   hwc.system.users.user.enable = true;         # Create eric user account
#   hwc.system.users.user.groups.development = true;  # Development permissions
#   hwc.system.users.emergencyEnable = true;     # Emergency root access (migration only)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.users;
  paths = config.hwc.paths;
in
{
  #============================================================================
  # OPTIONS - User Management Configuration
  #============================================================================

  options.hwc.system.users = {
    enable = lib.mkEnableOption "Enable HWC user management system";
    emergencyEnable = lib.mkEnableOption "Enable emergency root access during migration";

    user = {
      enable = lib.mkEnableOption "Eric user account configuration";

      name = lib.mkOption { 
        type = lib.types.str; 
        default = "eric"; 
        description = "Username for the primary user account";
      };
      
      description = lib.mkOption { 
        type = lib.types.str; 
        default = "Eric - Heartwood Craft"; 
        description = "Full name description for user account";
      };
      
      shell = lib.mkOption { 
        type = lib.types.package; 
        default = pkgs.zsh; 
        description = "Default shell for user account";
      };

      useSecrets = lib.mkOption { 
        type = lib.types.bool; 
        default = true; 
        description = "Use agenix secrets for user password management";
      };

      fallbackPassword = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "il0wwlm?";
        description = "Fallback password if useSecrets is false. Must be set if useSecrets is false.";
      };
   
      groups = {
        basic = lib.mkEnableOption "basic user groups (wheel, networkmanager)";
        media = lib.mkEnableOption "media access groups (video, audio)";
        development = lib.mkEnableOption "development groups (docker, podman)";
        virtualization = lib.mkEnableOption "virtualization groups (libvirtd, kvm)";
        hardware = lib.mkEnableOption "hardware access groups (input, uucp)";
      };

      ssh = {
        enable = lib.mkEnableOption "SSH configuration for user";

        useSecrets = lib.mkOption {
          type = lib.types.bool;
          default = cfg.user.useSecrets;
          description = "Use agenix secrets for SSH keys";
        };

        fallbackKey = lib.mkOption {
          type = lib.types.str;
          default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICubgcmg6aBisQC+MWRC4RWOY8zIHEl42O7bTbzyCiGB eriqueo@proton.me";
          description = "Fallback SSH public key if secrets not available";
        };
      };

      environment = {
        enablePaths = lib.mkEnableOption "export HWC path environment variables";
        enableZsh = lib.mkEnableOption "ZSH system-level configuration";
      };
    };
  };

  #============================================================================
  # IMPLEMENTATION - User Account and Environment
  #============================================================================

  config = lib.mkIf (cfg.enable && cfg.user.enable) {
    users.mutableUsers = false;

    #=========================================================================
    # SYSTEM-LEVEL ENVIRONMENT CONFIGURATION
    #=========================================================================

    # ZSH system enablement (required for user shell)
    programs.zsh.enable = lib.mkIf cfg.user.environment.enableZsh true;

    # Core system packages for user environment
    environment.systemPackages = with pkgs; [
      # Core utilities
      vim git wget curl htop tmux

      # Modern Unix tools
      ncdu tree ripgrep fd bat eza zoxide fzf

      # User environment tools
      which diffutils less
    ];

    # Font configuration for user applications
    fonts.packages = with pkgs; [
      nerd-fonts.caskaydia-cove
    ];

    #=========================================================================
    # SECURITY INTEGRATION & VALIDATION
    #=========================================================================
    assertions = [
      # User and security assertions:
      {
        assertion = !cfg.user.useSecrets || config.hwc.security.enable;
        message = "hwc.system.users.useSecrets requires hwc.security.enable = true (via security profile)";
      }
      {
        assertion = !cfg.user.ssh.useSecrets || config.hwc.security.enable;
        message = "hwc.system.users.ssh.useSecrets requires hwc.security.enable = true (via security profile)";
      }
      {
        assertion = !cfg.user.useSecrets || (config.hwc.security.materials.userInitialPasswordFile != null);
        message = "CRITICAL: useSecrets enabled but user-initial-password secret not available - this would lock you out! Disable useSecrets or ensure secret exists.";
      }
      {
        assertion = !cfg.user.ssh.useSecrets || (config.hwc.security.materials.userSshPublicKeyFile != null);
        message = "CRITICAL: SSH useSecrets enabled but user-ssh-public-key secret not available - this would lock you out of SSH! Disable useSecrets or ensure secret exists.";
      }
      {
        assertion = cfg.user.useSecrets || (cfg.user.fallbackPassword != null);
        message = "CRITICAL: hwc.system.users.useSecrets is false, but no fallbackPassword is set. This would create a user with no password and lock you out.";
      }
    ];
  };
}