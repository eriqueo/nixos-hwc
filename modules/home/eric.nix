# modules/home/eric.nix - Charter v3 User Configuration
#
# HWC User Environment Management (Charter v3)
# Consolidated user configuration with toggle-based feature control
#
# DEPENDENCIES:
#   Upstream: modules/security/secrets.nix (user secrets)
#   Upstream: modules/system/paths.nix (user paths)
#
# USED BY:
#   Downstream: profiles/base.nix (basic user setup)
#   Downstream: profiles/workstation.nix (user desktop environment)
#
# IMPORTS REQUIRED IN:
#   - profiles/base.nix: ../modules/home/eric.nix
#
# USAGE:
#   hwc.home.user.enable = true;              # Basic user account
#   hwc.home.groups.development = true;       # Development permissions
#   hwc.home.ssh.enable = true;               # SSH configuration
#
# VALIDATION:
#   - Requires hwc.security.secrets.user = true for secret integration
#   - Creates user with proper groups and permissions

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home;
  paths = config.hwc.paths;

  # Import script utilities
 # scripts = import ../../lib/scripts.nix { inherit lib pkgs config; };
in {
  #============================================================================
  # OPTIONS - User Environment Configuration
  #============================================================================

  options.hwc.home = {
    user = {
      enable = lib.mkEnableOption "Eric user account configuration";

      name = lib.mkOption {
        type = lib.types.str;
        default = "eric";
        description = "Username for the primary user";
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

      useSecrets = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use agenix secrets for user configuration";
      };
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

  config = lib.mkIf cfg.user.enable {

    systemd.services."home-manager-${cfg.user.name}" = {
      requires = [ "agenix.service" ];
      after = [ "agenix.service" ];
    };

    #=========================================================================
    # USER ACCOUNT DEFINITION
    #=========================================================================
    users.users.${cfg.user.name} = {
      isNormalUser = true;
      home = paths.user.home;
      description = cfg.user.description;
      shell = cfg.user.shell;

      # Dynamic group membership based on toggles
      extraGroups = [ ]
        ++ lib.optionals cfg.groups.basic [ "wheel" "networkmanager" ]
        ++ lib.optionals cfg.groups.media [ "video" "audio" "render" ]
        ++ lib.optionals cfg.groups.development [ "docker" "podman" ]
        ++ lib.optionals cfg.groups.virtualization [ "libvirtd" "kvm" ]
        ++ lib.optionals cfg.groups.hardware [ "input" "uucp" "dialout" ];

      # SSH keys are now managed through Home Manager below
      # to avoid the keyFiles/readFile incompatibility with agenix

      # Initial password - use secrets if available
      initialPassword =
        if cfg.user.useSecrets && config.age.secrets ? user-initial-password
        then null  # Password will be read from secret file
        else "il0wwlm?";  # Fallback password (matches your current password)

      # If using secrets, set password hash from secret file
      hashedPasswordFile =
        if cfg.user.useSecrets && config.age.secrets ? user-initial-password
        then config.age.secrets.user-initial-password.path
        else null;
    };

    #=========================================================================
    # SYSTEM-LEVEL ENVIRONMENT CONFIGURATION
    #=========================================================================

    # ZSH system enablement (required for user shell)
    programs.zsh.enable = lib.mkIf cfg.environment.enableZsh true;

    # Core system packages for user environment
    environment.systemPackages = with pkgs; [
      # Core utilities
      vim git wget curl htop tmux

      # Modern Unix tools
      ncdu tree ripgrep fd bat eza zoxide fzf

      # User environment tools
      which diffutils less

      # Script utilities (from lib/scripts.nix)
    ] ++ (lib.optionals cfg.environment.enablePaths [
      # Path-related utilities when path management is enabled
     (pkgs.writeShellScriptBin "hwc-paths" ''
        echo "HWC Path Configuration:"
        env | grep "^HWC_" | sort
      '')
    ]);

    #=========================================================================
    # USER DIRECTORY PERMISSIONS AND OWNERSHIP
    #=========================================================================

    # User home directory ownership (using paths module)
    systemd.tmpfiles.rules = [
      "Z ${paths.user.home} - ${cfg.user.name} users - -"
      "Z ${paths.user.ssh} 0700 ${cfg.user.name} users - -"
      "d ${paths.user.config} 0755 ${cfg.user.name} users -"
    ];

    #=========================================================================
    # OPTIONAL USER GROUPS CREATION
    #=========================================================================

    # Create media groups if enabled
    users.groups = lib.mkIf cfg.groups.media {
      render = lib.mkForce { gid = 2002; };  # GPU rendering group
    };

    #=========================================================================
    # HOME MANAGER CONFIGURATION
    #=========================================================================

    home-manager.users.${cfg.user.name} = {
      home.stateVersion = "24.05";
      home.file.".ssh/authorized_keys" =
        if cfg.ssh.useSecrets then {
          source = config.age.secrets.user-ssh-public-key.path;
        } else {
          text = cfg.ssh.fallbackKey;
        };
    };
    #=========================================================================
    # SECURITY INTEGRATION
    #=========================================================================

    # Ensure secrets are available if using them
    assertions = [
      {
        assertion = !cfg.user.useSecrets || config.hwc.security.enable;
        message = "hwc.home.user.useSecrets requires hwc.security.enable = true";
      }
      {
        assertion = !cfg.ssh.useSecrets || config.hwc.security.secrets.user;
        message = "hwc.home.ssh.useSecrets requires hwc.security.secrets.user = true";
      }
    ];
  };
}
