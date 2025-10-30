{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.system.users;
in {
  config = lib.mkIf (cfg.enable && cfg.user.enable) {
    users.mutableUsers = false;

    # Shared secrets group for service access
    users.groups.secrets = {};

    users.users.${cfg.user.name} = {
      isNormalUser = true;
      home = "/home/${cfg.user.name}";
      group = "users";
      shell = cfg.user.shell;
      description = cfg.user.description;

      extraGroups =
        (lib.optionals cfg.user.groups.basic          [ "wheel" "networkmanager" "bluetooth" "secrets" ]) ++
        (lib.optionals cfg.user.groups.media          [ "video" "audio" "render" ]) ++
        (lib.optionals cfg.user.groups.development    [ "docker" "podman" ]) ++
        (lib.optionals cfg.user.groups.virtualization [ "libvirtd" "kvm" ]) ++
        (lib.optionals cfg.user.groups.hardware       [ "input" "uucp" ]);

      # Smart password configuration: secrets when available, fallback when not
      initialPassword = lib.mkIf (
        (!cfg.user.useSecrets || config.hwc.secrets.api.userInitialPasswordFile == null)
        && cfg.user.fallbackPassword != null
      ) cfg.user.fallbackPassword;

      hashedPasswordFile = lib.mkIf (cfg.user.useSecrets && config.hwc.secrets.api.userInitialPasswordFile != null)
        config.age.secrets.user-initial-password.path;

      openssh.authorizedKeys.keys = lib.mkIf cfg.user.ssh.enable (
        if cfg.user.ssh.useSecrets && config.hwc.secrets.api.userSshPublicKeyFile != null then
          [ (builtins.readFile config.age.secrets.user-ssh-public-key.path) ]
        else
          cfg.user.ssh.fallbackKey
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
        assertion = cfg.user.fallbackPassword != null;
        message = "CRITICAL: No fallbackPassword set. This is required for emergency access when agenix fails.";
      }
    ];

    # Warnings for fallback scenarios
    warnings = lib.optionals (cfg.user.useSecrets && config.hwc.secrets.api.userInitialPasswordFile == null) [
      ''
        ##################################################################
        # AGENIX FALLBACK ACTIVE: user-initial-password not available   #
        # Using fallback password for emergency access.                 #
        # This is expected when agenix/secrets are broken.              #
        ##################################################################
      ''
    ] ++ lib.optionals (cfg.user.ssh.useSecrets && config.hwc.secrets.api.userSshPublicKeyFile == null) [
      ''
        ##################################################################
        # AGENIX FALLBACK ACTIVE: user-ssh-public-key not available     #
        # Using fallback SSH keys for emergency access.                 #
        # This is expected when agenix/secrets are broken.              #
        ##################################################################
      ''
    ];
  };
}
