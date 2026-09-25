# domains/business/firefly/parts/explorer.nix
#
# Workbench Finance area. Caddy is the only process allowed to connect to the
# root-owned Unix socket; the application then maps Caddy's overwritten
# X-Forwarded-For address through tailscaled WhoIs before serving any API data.
# Persistent data remains in Firefly. The explorer keeps only a bounded,
# replaceable in-memory cache (default 60 seconds), so there is no cleanup job.
{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.business.firefly;
  explorer = cfg.explorer;
  fireflyBase = "http://127.0.0.1:${toString cfg.reverseProxy.coreInternalPort}";
in
{
  config = lib.mkIf (cfg.enable && explorer.enable) {
    systemd.sockets.firefly-explorer = {
      description = "Firefly Explorer private Caddy socket";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = explorer.socketPath;
        SocketUser = "root";
        SocketGroup = "root";
        SocketMode = "0600";
        RemoveOnStop = true;
      };
    };

    systemd.services.firefly-explorer = {
      description = "Workbench Finance recurring-payment explorer";
      wantedBy = [ "multi-user.target" ];
      requires = [ "firefly-explorer.socket" "podman-firefly.service" ];
      after = [
        "firefly-explorer.socket"
        "podman-firefly.service"
        "tailscaled.service"
        "agenix.service"
      ];

      environment = {
        FIREFLY_BASE_URL = fireflyBase;
        FIREFLY_TOKEN_FILE = explorer.patFile;
        FIREFLY_ASSET_ACCOUNT_ID = toString explorer.assetAccountId;
        FIREFLY_ACCOUNT_NAME = explorer.accountName;
        FIREFLY_HISTORY_START = explorer.historyStart;
        FIREFLY_EXPLORER_ALLOWED_LOGIN = explorer.allowedLogin;
        FIREFLY_EXPLORER_ORIGIN = explorer.appUrl;
        FIREFLY_EXPLORER_WORKBENCH_HOME = "https://workbench.${config.hwc.networking.shared.vhostDomain}/";
        FIREFLY_EXPLORER_CACHE_SECONDS = toString explorer.cacheSeconds;
        FIREFLY_EXPLORER_PROTECTED_TAGS = lib.concatStringsSep "," explorer.protectedTags;
        FIREFLY_EXPLORER_COVERAGE_NOTE = explorer.coverageNote;
      };

      serviceConfig = {
        Type = "simple";
        User = lib.mkForce "eric";
        Group = "users";
        SupplementaryGroups = [ "secrets" ];
        # The app checks Firefly at startup and exits if it is not answering;
        # podman-firefly is "active" before PHP listens, so a boot (or a
        # socket hit right after a switch) lost that race (hwc-work,
        # 2026-09-25). Wait for it, bounded, then start or fail loudly.
        ExecStartPre = pkgs.writeShellScript "firefly-explorer-wait" ''
          for i in $(${pkgs.coreutils}/bin/seq 1 36); do
            ${pkgs.curl}/bin/curl -fs -o /dev/null -m 5 ${fireflyBase}/ && exit 0
            ${pkgs.coreutils}/bin/sleep 5
          done
          echo "firefly-explorer: Firefly at ${fireflyBase} did not answer within 180s" >&2
          exit 1
        '';
        ExecStart = "${explorer.package}/bin/firefly-explorer --fd 3";
        Restart = "no";
        UMask = "0077";

        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
      };
    };

    assertions = [
      {
        assertion = config.age.secrets ? firefly-explorer-pat;
        message = "Firefly Explorer requires the dedicated firefly-explorer-pat agenix secret.";
      }
      {
        assertion = explorer.patFile == config.age.secrets.firefly-explorer-pat.path;
        message = "Firefly Explorer must read its dedicated agenix token path.";
      }
      {
        assertion = lib.hasPrefix "https://" explorer.appUrl;
        message = "Firefly Explorer appUrl must be an HTTPS origin.";
      }
    ];
  };
}
