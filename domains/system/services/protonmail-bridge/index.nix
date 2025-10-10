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
        RuntimeDirectory = "proton-bridge";
        WorkingDirectory = "/var/lib/proton-bridge";

        UMask = "0077";
        Restart = "on-failure";
        RestartSec = "30s";
        StartLimitIntervalSec = 600;
        StartLimitBurst = 3;

        UnsetEnvironment = "PATH GNOME_KEYRING_CONTROL SSH_AUTH_SOCK DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS";
        Environment = [
          "HOME=/var/lib/proton-bridge"
          "XDG_CONFIG_HOME=/var/lib/proton-bridge/config"
          "XDG_DATA_HOME=/var/lib/proton-bridge/data"
          "XDG_CACHE_HOME=/var/lib/proton-bridge/cache"
          "PATH=/run/current-system/sw/bin"
        ];

        ExecStartPre = pkgs.writeShellScript "proton-bridge-init" ''
          ${pkgs.procps}/bin/pgrep -u eric -f protonmail-bridge >/dev/null 2>&1 && {
            echo "user-scoped protonmail-bridge detected; stop it before starting system unit" >&2
            exit 1
          }

          ${pkgs.coreutils}/bin/install -d -m 700 -o protonbridge -g protonbridge /var/lib/proton-bridge/config/protonmail/bridge-v3/insecure
          ${pkgs.coreutils}/bin/install -d -m 700 -o protonbridge -g protonbridge /var/lib/proton-bridge/data

          if [ ! -f /var/lib/proton-bridge/config/protonmail/bridge-v3/keychain.json ]; then
            printf '{"Helper":"","DisableTest":true}\n' > /var/lib/proton-bridge/config/protonmail/bridge-v3/keychain.json
            ${pkgs.coreutils}/bin/chown protonbridge:protonbridge /var/lib/proton-bridge/config/protonmail/bridge-v3/keychain.json
            ${pkgs.coreutils}/bin/chmod 600 /var/lib/proton-bridge/config/protonmail/bridge-v3/keychain.json
          fi
        '';

        ExecStart = "${pkgs.coreutils}/bin/env -i HOME=/var/lib/proton-bridge XDG_CONFIG_HOME=/var/lib/proton-bridge/config XDG_DATA_HOME=/var/lib/proton-bridge/data XDG_CACHE_HOME=/var/lib/proton-bridge/cache PATH=/run/current-system/sw/bin ${bridgePkg}/bin/protonmail-bridge --noninteractive --log-level warn";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        BindReadOnlyPaths = [ "/etc/ssl/certs" ];
        CapabilityBoundingSet = "";
        SystemCallFilter = [ "@system-service" ];
      };
    };
  };
}