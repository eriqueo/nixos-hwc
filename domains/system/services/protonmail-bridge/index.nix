{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.system.services.protonmail-bridge;
  bridgePkg = pkgs.protonmail-bridge;
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
  users.groups.protonbridge = {};
  users.users.protonbridge = {
    isSystemUser = true;
    description = "Proton Bridge service user";
    home = "/var/lib/proton-bridge";
    createHome = true;
    group = "protonbridge";
  };

  systemd.services.protonmail-bridge = {
    description = "Proton Mail Bridge (headless, isolated)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "protonbridge";
      Group = "protonbridge";
      StateDirectory = "proton-bridge";
      ConfigurationDirectory = "proton-bridge";
      RuntimeDirectory = "proton-bridge";
      WorkingDirectory = "/var/lib/proton-bridge";
      UnsetEnvironment = "PATH GNOME_KEYRING_CONTROL SSH_AUTH_SOCK DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS";
      Environment = [
        "HOME=/var/lib/proton-bridge"
        "XDG_CONFIG_HOME=/var/lib/proton-bridge/config"
        "XDG_DATA_HOME=/var/lib/proton-bridge/data"
        "XDG_CACHE_HOME=/var/lib/proton-bridge/cache"
        "PATH=/run/current-system/sw/bin"
      ];
      ExecStartPre = pkgs.writeShellScript "proton-bridge-init" ''
        install -d -m 700 -o protonbridge -g protonbridge /var/lib/proton-bridge/config/protonmail/bridge-v3/insecure
        install -d -m 700 -o protonbridge -g protonbridge /var/lib/proton-bridge/data
        if [ ! -f /var/lib/proton-bridge/config/protonmail/bridge-v3/keychain.json ]; then
          printf '{"Helper":"","DisableTest":true}\n' > /var/lib/proton-bridge/config/protonmail/bridge-v3/keychain.json
          chown protonbridge:protonbridge /var/lib/proton-bridge/config/protonmail/bridge-v3/keychain.json
          chmod 600 /var/lib/proton-bridge/config/protonmail/bridge-v3/keychain.json
        fi
      '';
      ExecStart = "${pkgs.coreutils}/bin/env -i HOME=/var/lib/proton-bridge XDG_CONFIG_HOME=/var/lib/proton-bridge/config XDG_DATA_HOME=/var/lib/proton-bridge/data XDG_CACHE_HOME=/var/lib/proton-bridge/cache PATH=/run/current-system/sw/bin ${bridgePkg}/bin/protonmail-bridge --noninteractive --log-level warn";
      Restart = "on-failure";
      RestartSec = "10s";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      PrivateTmp = true;
      BindReadOnlyPaths = [ "/etc/ssl/certs" ];
      CapabilityBoundingSet = "";
      SystemCallFilter = [ "@system-service" ];
    };
  };
  }
}