# nixos-hwc/modules/home/eric.nix
#
# ERIC USER ENVIRONMENT - Primary user configuration
# Defines the main user account, groups, and environment settings
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.* (modules/system/paths.nix)
#   - config.hwc.security.secrets.* (modules/security/secrets.nix)
#
# USED BY (Downstream):
#   - profiles/base.nix (enables via hwc.home.user.enable)
#   - profiles/workstation.nix (imports for desktop environment)
#
# IMPORTS REQUIRED IN:
#   - profiles/base.nix: ../modules/home/core/eric.nix
#
# USAGE:
#   hwc.home.user.enable = true;              # Basic user account
#   hwc.home.groups.development = true;       # Development permissions
#   hwc.home.ssh.enable = true;               # SSH configuration

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.users;
  paths = config.hwc.paths;

  # Import script utilities
 # scripts = import ../../lib/scripts.nix { inherit lib pkgs config; };
in {
  #============================================================================
  # OPTIONS - User Environment Configuration
  #============================================================================

  options.hwc.system.users.user = {
      enable = lib.mkEnableOption "Eric user account configuration";

      name = lib.mkOption { type = lib.types.str; default = "eric"; };
      description = lib.mkOption { type = lib.types.str; default = "Eric - Heartwood Craft"; };
      shell = lib.mkOption { type = lib.types.package; default = pkgs.zsh; };

      useSecrets = lib.mkOption { type = lib.types.bool; default = true; };

      
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

  #============================================================================
  # IMPLEMENTATION - User Account and Environment
  #============================================================================

  config = lib.mkIf (cfg.enable && cfg.user.enable) {
    users.mutableUsers = false;

    users.users.root = lib.mkIf (!cfg.user.useSecrets && cfg.user.fallbackPassword != null) {

      hashedPassword = null;
      
    };
    users.users.${cfg.user.name} = {
      isNormalUser = true;
      description  = cfg.user.description;
      shell        = cfg.user.shell;

    extraGroups = 
      (lib.optionals cfg.user.groups.basic            [ "wheel" "networkmanager" ]) ++
      (lib.optionals cfg.user.groups.media            [ "video" "audio"]) ++
      (lib.optionals cfg.user.groups.development      [ "docker" "podman"]) ++
      (lib.optionals cfg.user.groups.virtualization   [ "libvirtd" ]) ++
      (lib.optionals cfg.user.groups.hardware         [ "input" "uucp"]);

    initialPassword = lib.mkIf (!cfg.user.useSecrets && cfg.user.fallbackPassword != null)
      cfg.user.fallbackPassword;
    };  
   
    

    
  # User system services handled by infrastructure layer
  # See: modules/infrastructure/user-services.nix
  # The user account definition has been moved to:
  # - modules/system/users.nix (Charter v4 compliant)
  # - Configured in profiles/base.nix with hwc.system.users options
  # - Emergency access available via hwc.system.users.emergencyEnable

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

      # Script utilities would be provided by infrastructure layer if needed
    ];

    # Font configuration for user applications
    fonts.packages = with pkgs; [
      (nerdfonts.override { fonts = [ "CascadiaCode" ]; })
    ];

    # Hardware access and system setup handled by infrastructure layer
    # See: modules/infrastructure/user-hardware-access.nix

    #=========================================================================
    # HOME MANAGER CONFIGURATION
    #=========================================================================
    # Home-Manager configuration now handled centrally in profiles/workstation.nix
    # This module only provides NixOS-level user configuration
  #=========================================================================
  # SECURITY INTEGRATION & VALIDATION
  #=========================================================================
  assertions = [
    # User and security assertions:
    {
      assertion = !cfg.user.useSecrets || config.hwc.system.secrets.enable;
      message = "hwc.home.user.useSecrets requires hwc.security.enable = true";
    }
    {
      assertion = !cfg.user.ssh.useSecrets || config.hwc.system.secrets.enable;
      message = "hwc.home.ssh.useSecrets requires hwc.security.secrets.user = true";
    }
    {
      assertion = !cfg.user.useSecrets || (config.age.secrets ? "user-initial-password");
      message = "CRITICAL: useSecrets enabled but user-initial-password secret not available - this would lock you out! Disable useSecrets or ensure secret exists.";
    }
    {
      assertion = !cfg.user.ssh.useSecrets || (config.age.secrets ? "user-ssh-public-key");
      message = "CRITICAL: SSH useSecrets enabled but user-ssh-public-key secret not available - this would lock you out of SSH! Disable useSecrets or ensure secret exists.";
    }

    # =======================================================================
    # ADD THIS FINAL ASSERTION
    # This ensures that if secrets are disabled, a fallback password MUST
    # be provided, preventing a user with no password.
    # =======================================================================
    {
      assertion = cfg.user.useSecrets || (cfg.user.fallbackPassword != null);
      message = "CRITICAL: hwc.home.user.useSecrets is false, but no fallbackPassword is set. This would create a user with no password and lock you out.";
    }
  ];
};
}
