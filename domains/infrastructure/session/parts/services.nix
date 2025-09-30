# HWC Charter Module/domains/infrastructure/user-services.nix
#
# USER SERVICES - System-level user service management (infrastructure layer)
# Provides systemd services for user environment setup and secret integration
#
# DEPENDENCIES (Upstream):
#   - config.age.secrets.* (agenix secret management)
#   - config.hwc.paths.* (modules/system/paths.nix)
#   - config.hwc.home.* (modules/home/eric.nix)
#
# USED BY (Downstream):
#   - profiles/*.nix (enables via hwc.infrastructure.userServices.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/infrastructure/user-services.nix
#
# USAGE:
#   hwc.infrastructure.session.services.enable = true;
#   hwc.infrastructure.session.services.username = "eric";  # defaults to config.hwc.home.user.name

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.session.services;
  usersCfg = config.hwc.system.users;
  paths = config.hwc.paths;
in {
  #============================================================================
  # IMPLEMENTATION - User system services
  #============================================================================

  config = lib.mkIf cfg.enable {

    # DISABLED: Modern agenix uses activation scripts, not systemd services
    # Secrets are decrypted during system activation before home-manager runs
    # systemd.services."home-manager-${cfg.username}" = {
    #   requires = [ "agenix.service" ];
    #   after = [ "agenix.service" ];
    # };

    # SSH key setup service (handles both secrets and fallback)
    systemd.services."setup-ssh-keys-${cfg.username}" = lib.mkIf (usersCfg.user.ssh.enable or false) {
      description = "Setup SSH authorized keys for ${cfg.username}";
      wantedBy = [ "multi-user.target" ];
      after = [ "agenix.service" ];
      requires = [ "agenix.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };
      script = if (usersCfg.user.ssh.useSecrets or false) then ''
        # Wait for the secret to be available
        while [ ! -f "${config.age.secrets.user-ssh-public-key.path}" ]; do
          sleep 1
        done

        # Create .ssh directory if it doesn't exist
        mkdir -p ${paths.user.home}/.ssh
        chmod 700 ${paths.user.home}/.ssh
        chown ${cfg.username}:users ${paths.user.home}/.ssh

        # Copy the public key to authorized_keys
        cp "${config.age.secrets.user-ssh-public-key.path}" ${paths.user.home}/.ssh/authorized_keys
        chmod 600 ${paths.user.home}/.ssh/authorized_keys
        chown ${cfg.username}:users ${paths.user.home}/.ssh/authorized_keys
      '' else ''
        # Create .ssh directory if it doesn't exist
        mkdir -p ${paths.user.home}/.ssh
        chmod 700 ${paths.user.home}/.ssh
        chown ${cfg.username}:users ${paths.user.home}/.ssh

        # Write fallback key to authorized_keys
        cat > ${paths.user.home}/.ssh/authorized_keys <<EOF
        ${usersCfg.user.ssh.fallbackKey or ""}
        EOF
        chmod 600 ${paths.user.home}/.ssh/authorized_keys
        chown ${cfg.username}:users ${paths.user.home}/.ssh/authorized_keys
      '';
    };
  };
}