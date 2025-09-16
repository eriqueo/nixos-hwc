{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.system.users;
in {
  config = lib.mkIf (cfg.enable && cfg.user.enable) {
    users.mutableUsers = false;

    users.users.${cfg.user.name} = {
      isNormalUser = true;
      home = "/home/${cfg.user.name}";
      shell = cfg.user.shell;
      description = cfg.user.description;
      
      extraGroups = 
        (lib.optionals cfg.user.groups.basic            [ "wheel" "networkmanager" ]) ++
        (lib.optionals cfg.user.groups.media            [ "video" "audio"]) ++
        (lib.optionals cfg.user.groups.development      [ "docker" "podman"]) ++
        (lib.optionals cfg.user.groups.virtualization   [ "libvirtd" "kvm" ]) ++
        (lib.optionals cfg.user.groups.hardware         [ "input" "uucp"]);

      initialPassword = lib.mkIf (!cfg.user.useSecrets && cfg.user.fallbackPassword != null)
        cfg.user.fallbackPassword;
    };

    # ZSH system enablement (required for user shell)
    programs.zsh.enable = lib.mkIf cfg.user.environment.enableZsh true;

    # Core system packages for user environment  
    environment.systemPackages = lib.mkIf cfg.enable (with pkgs; [
      # Core utilities
      vim git wget curl htop tmux

      # Modern Unix tools
      ncdu tree ripgrep fd bat eza zoxide fzf

      # User environment tools
      which diffutils less
    ]);

    # Font configuration for user applications
    fonts.packages = lib.mkIf cfg.enable (with pkgs; [
      nerd-fonts.caskaydia-cove
    ]);

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