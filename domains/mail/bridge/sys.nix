{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.mail.bridge.system;
  relay = config.hwc.mail.bridge.relay;
  bridgePkg = pkgs.protonmail-bridge;

  # Get username from system configuration
  userName = config.hwc.system.users.user.name;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.mail.bridge.system = {
    enable = lib.mkEnableOption "Proton Mail Bridge system service";
  };

  # Plain TCP relay for the bridge's SMTP/IMAP ports between hosts. The
  # bridge (one Proton session) runs on one host and binds 127.0.0.1 only;
  # the host that runs it exposes the ports on its tailnet address
  # (listenAddress = tailnet IP, targetAddress = 127.0.0.1) and a host whose
  # consumers still expect a loopback bridge relays 127.0.0.1 to it
  # (listenAddress = 127.0.0.1, targetAddress = the bridge host). Traffic is
  # the bridge's plaintext loopback protocol, carried inside WireGuard.
  options.hwc.mail.bridge.relay = {
    enable = lib.mkEnableOption "TCP relay of the Proton Bridge SMTP/IMAP ports";
    listenAddress = lib.mkOption {
      type = lib.types.str;
      example = "127.0.0.1";
      description = "Address the relay binds on this host.";
    };
    targetAddress = lib.mkOption {
      type = lib.types.str;
      example = "100.77.38.32";
      description = "Address the bridge answers on (127.0.0.1 on the bridge host).";
    };
    ports = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ 1025 1143 ];
      description = "Bridge ports to relay (SMTP, IMAP).";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkMerge [
  (lib.mkIf relay.enable {
    # One socat per port. Restarts forever: at boot the tailnet address may
    # not exist yet, and on the consuming host 127.0.0.1:<port> is only free
    # once a local bridge is gone.
    systemd.services = lib.listToAttrs (map (port: {
      name = "proton-bridge-relay-${toString port}";
      value = {
        description = "Proton Bridge relay ${relay.listenAddress}:${toString port} -> ${relay.targetAddress}:${toString port}";
        after = [ "network-online.target" "tailscaled.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        startLimitIntervalSec = 0;
        serviceConfig = {
          ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:${toString port},bind=${relay.listenAddress},fork,reuseaddr TCP:${relay.targetAddress}:${toString port}";
          Restart = "always";
          RestartSec = 5;
          DynamicUser = true;
          NoNewPrivileges = true;
        };
      };
    }) relay.ports);

    assertions = [
      {
        assertion = relay.listenAddress != relay.targetAddress;
        message = "hwc.mail.bridge.relay: listenAddress and targetAddress must differ (a relay to itself loops).";
      }
    ];
  })

  (lib.mkIf cfg.enable {
    users.groups.protonbridge = {};
    users.users.protonbridge = {
      isSystemUser = true;
      description = "Proton Bridge service user";
      home = "/var/lib/proton-bridge";
      createHome = true;
      group = "protonbridge";
      extraGroups = [ "secrets" ];
    };

    systemd.services.protonmail-bridge = {
      description = "Proton Mail Bridge (headless, isolated)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        User = lib.mkForce "eric";
        Group = lib.mkForce "users";

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
        PermissionsStartOnly = true;

        ExecStartPre = pkgs.writeShellScript "proton-bridge-init" ''
          if ${pkgs.procps}/bin/pgrep -u ${userName} -f "protonmail-bridge" | ${pkgs.findutils}/bin/xargs -r ${pkgs.procps}/bin/ps -p 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "/bin/protonmail-bridge"; then
            echo "user-scoped protonmail-bridge detected; stop it before starting system unit" >&2
            exit 1
          fi

          ${pkgs.coreutils}/bin/install -d -m 700 -o eric -g users /var/lib/proton-bridge/config/protonmail/bridge-v3/insecure
          ${pkgs.coreutils}/bin/install -d -m 700 -o eric -g users /var/lib/proton-bridge/data
          ${pkgs.coreutils}/bin/install -d -m 700 -o eric -g users /var/lib/proton-bridge/cache

          if [ ! -f /var/lib/proton-bridge/config/protonmail/bridge-v3/keychain.json ]; then
            printf '{"Helper":"","DisableTest":true}\n' > /var/lib/proton-bridge/config/protonmail/bridge-v3/keychain.json
            ${pkgs.coreutils}/bin/chown eric:users /var/lib/proton-bridge/config/protonmail/bridge-v3/keychain.json
            ${pkgs.coreutils}/bin/chmod 600 /var/lib/proton-bridge/config/protonmail/bridge-v3/keychain.json
          fi
        '';

        ExecStart = "${pkgs.coreutils}/bin/env -i HOME=/var/lib/proton-bridge XDG_CONFIG_HOME=/var/lib/proton-bridge/config XDG_DATA_HOME=/var/lib/proton-bridge/data XDG_CACHE_HOME=/var/lib/proton-bridge/cache PATH=/run/current-system/sw/bin ${bridgePkg}/bin/protonmail-bridge --noninteractive --log-level warn";

        ExecStartPost = pkgs.writeShellScript "proton-bridge-export-cert" ''
          set -eu
          # wait briefly until IMAP port is ready
          for i in $(${pkgs.util-linux}/bin/seq 1 15); do
            if ${pkgs.openssl}/bin/openssl s_client -starttls imap -connect 127.0.0.1:1143 -quiet </dev/null >/dev/null 2>&1; then
              break
            fi
            ${pkgs.coreutils}/bin/sleep 1
          done
          # extract server certificate and store as local trust just for mbsync
          ${pkgs.coreutils}/bin/mkdir -p /etc/ssl/local
          ${pkgs.openssl}/bin/openssl s_client -starttls imap -connect 127.0.0.1:1143 -showcerts </dev/null \
            | ${pkgs.gnused}/bin/sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' \
            | ${pkgs.coreutils}/bin/tee /etc/ssl/local/proton-bridge.pem >/dev/null
          ${pkgs.coreutils}/bin/chmod 0644 /etc/ssl/local/proton-bridge.pem
        '';

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        BindReadOnlyPaths = [ "/etc/ssl/certs" ];
        CapabilityBoundingSet = "";
        SystemCallFilter = [ "@system-service" ];
      };
    };
    assertions = [];
  })
  ];

}
