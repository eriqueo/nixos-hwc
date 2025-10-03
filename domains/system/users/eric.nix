{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.system.users;
in {
  config = lib.mkIf (cfg.enable && cfg.user.enable) {
    users.mutableUsers = false;

    users.users.${cfg.user.name} = {
      isNormalUser = true;
      home = "/home/${cfg.user.name}";
      group = "users";
      shell = cfg.user.shell;
      description = cfg.user.description;

      extraGroups =
        (lib.optionals cfg.user.groups.basic          [ "wheel" "networkmanager" ]) ++
        (lib.optionals cfg.user.groups.media          [ "video" "audio" "render" ]) ++
        (lib.optionals cfg.user.groups.development    [ "docker" "podman" ]) ++
        (lib.optionals cfg.user.groups.virtualization [ "libvirtd" "kvm" ]) ++
        (lib.optionals cfg.user.groups.hardware       [ "input" "uucp" ]);

      initialPassword = lib.mkIf (!cfg.user.useSecrets && cfg.user.fallbackPassword != null)
        cfg.user.fallbackPassword;

      hashedPasswordFile = lib.mkIf cfg.user.useSecrets
        config.age.secrets.user-initial-password.path;

      openssh.authorizedKeys.keys = lib.mkIf cfg.user.ssh.enable (
        if cfg.user.ssh.useSecrets then
          [ (builtins.readFile config.age.secrets.user-ssh-public-key.path) ]
        else
          [ cfg.user.ssh.fallbackKey ]
      );
    };

    programs.zsh.enable = true;

    environment.systemPackages = with pkgs; [
      vim git wget curl htop tmux
      ncdu tree ripgrep fd bat eza zoxide fzf
      which diffutils less
    ];

    assertions = [
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
