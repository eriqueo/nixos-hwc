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
        (lib.optionals cfg.user.groups.media            [ "video" "audio" "render" ]) ++
        (lib.optionals cfg.user.groups.development      [ "docker" "podman"]) ++
        (lib.optionals cfg.user.groups.virtualization   [ "libvirtd" "kvm" ]) ++
        (lib.optionals cfg.user.groups.hardware         [ "input" "uucp"]);

      initialPassword = lib.mkIf (!cfg.user.useSecrets && cfg.user.fallbackPassword != null)
        cfg.user.fallbackPassword;

      openssh.authorizedKeys.keys = lib.mkIf cfg.user.ssh.enable (
        if cfg.user.ssh.useSecrets then
          [ (builtins.readFile config.age.secrets.user-ssh-public-key.path) ]
        else
          [ cfg.user.ssh.fallbackKey ]
      );
    };

    # ZSH system enablement (required for user shell)
    programs.zsh.enable = lib.mkIf cfg.user.environment.enableZsh true;

    users.groups.render = lib.mkIf cfg.user.groups.media { gid = 2002; };

    systemd.tmpfiles.rules = lib.mkIf cfg.enable [
      "Z /home/${cfg.user.name} - ${cfg.user.name} users - -"
      "Z /home/${cfg.user.name}/.ssh 0700 ${cfg.user.name} users - -"
      "d /home/${cfg.user.name}/.config 0755 ${cfg.user.name} users -"
    ];

    environment.systemPackages = lib.mkIf cfg.enable (with pkgs; [
      vim git wget curl htop tmux
      ncdu tree ripgrep fd bat eza zoxide fzf
      which diffutils less
    ]);


    #=========================================================================
    # SECURITY INTEGRATION & VALIDATION
    #=========================================================================
    assertions = [
      # User and security assertions:
      {
        assertion = !cfg.user.useSecrets || config.hwc.secrets.enable;
        message = "hwc.system.users.useSecrets requires hwc.secrets.enable = true (via security profile)";
      }
      {
        assertion = !cfg.user.ssh.useSecrets || config.hwc.secrets.enable;
        message = "hwc.system.users.ssh.useSecrets requires hwc.secrets.enable = true (via security profile)";
      }
      {
        assertion = !cfg.user.useSecrets || (config.hwc.secrets.api.userInitialPasswordFile != null);
        message = "CRITICAL: useSecrets enabled but user-initial-password secret not available - this would lock you out! Disable useSecrets or ensure secret exists.";
      }
      {
        assertion = !cfg.user.ssh.useSecrets || (config.hwc.secrets.api.userSshPublicKeyFile != null);
        message = "CRITICAL: SSH useSecrets enabled but user-ssh-public-key secret not available - this would lock you out of SSH! Disable useSecrets or ensure secret exists.";
      }
      {
        assertion = cfg.user.useSecrets || (cfg.user.fallbackPassword != null);
        message = "CRITICAL: hwc.system.users.useSecrets is false, but no fallbackPassword is set. This would create a user with no password and lock you out.";
      }
    ];
  };
}