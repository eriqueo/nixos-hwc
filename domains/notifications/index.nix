# domains/notifications/index.nix
#
# Notifications Domain — delivery infrastructure for how messages reach humans.
#
# NAMESPACE: hwc.notifications.*
#
# All delivery flows through hwc-notify (domains/notifications/notify), the
# loopback dispatcher on :11600. Two front-ends onto that core:
#   - the HTTP port itself (machines / n8n POST NotificationInput JSON)
#   - hwc-alert (this domain's `send/cli.nix`) for humans + scripts
# The event-shaped notifiers (smartd / systemd OnFailure / backup) are thin
# adapters over hwc-alert. No Slack, no gotify, no n8n webhook path.
#
# USED BY:
#   - profiles/monitoring.nix (enables notification delivery)
#   - domains/monitoring/alerts (alert detection → delivery via _internal)
#   - domains/data/backup (backup success/failure notifications)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.notifications;
  enabled = cfg.enable;

  # Event-shaped notifiers (smartd / OnFailure / backup) — adapters over hwc-alert.
  notifyScripts = import ./send/notify-scripts.nix { inherit pkgs lib config; };

  # hwc-alert CLI — front-end onto :11600/notify.
  cliTool = import ./send/cli.nix { inherit pkgs lib config; };

in
{
  # OPTIONS
  options.hwc.notifications = {
    enable = lib.mkEnableOption "Notification delivery infrastructure (hwc-notify + hwc-alert)";

    #==========================================================================
    # CLI TOOL
    #==========================================================================
    send.cli = {
      enable = lib.mkEnableOption "hwc-alert CLI tool for sending alerts";

      defaultEndpoint = lib.mkOption {
        type = lib.types.str;
        default = "system";
        description = "Default source tag for CLI alerts (system, backup, smartd, services)";
      };

      defaultSeverity = lib.mkOption {
        type = lib.types.str;
        default = "info";
        description = "Default severity for CLI alerts (info, warning, critical)";
      };
    };

    #==========================================================================
    # INTERNAL OPTIONS (for cross-domain access)
    #==========================================================================
    _internal = {
      cliScript = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        internal = true;
        description = "Internal: hwc-alert CLI script package";
      };

      smartdNotify = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        internal = true;
        description = "Internal: smartd notification script package";
      };

      serviceFailureNotify = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        internal = true;
        description = "Internal: service failure notification script package";
      };

      backupNotify = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        internal = true;
        description = "Internal: backup notification script package";
      };
    };
  };

  imports = [
    ./notify/index.nix               # hwc-notify — the sole dispatcher
    ./canary.nix                     # delivery deadman probe (Discord + SMTP)
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {
    # Export internal script packages for cross-domain access
    hwc.notifications._internal = {
      cliScript = cliTool;
      smartdNotify = notifyScripts.smartdNotify;
      serviceFailureNotify = notifyScripts.serviceFailureNotify;
      backupNotify = notifyScripts.backupNotify;
    };

    # Install the event notifiers (+ hwc-alert when the CLI is enabled).
    environment.systemPackages = [
      notifyScripts.smartdNotify
      notifyScripts.serviceFailureNotify
      notifyScripts.backupNotify
    ] ++ lib.optional cfg.send.cli.enable cliTool;

    # =======================================================================
    # TMPFILES
    # =======================================================================
    # 2775 root:users so both root (systemd notifiers) and eric (interactive
    # hwc-alert) can write here; setgid keeps new files in the users group.
    systemd.tmpfiles.rules = [
      "d /var/log/hwc/notifications 2775 root users -"
    ];

    # =======================================================================
    # LOG ROTATION
    # =======================================================================
    services.logrotate.settings.hwc-notifications = {
      files = [ "/var/log/hwc/notifications/*.log" ];
      frequency = "weekly";
      rotate = 4;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      # The parent dir is intentionally group-writable (2775 root:users, above);
      # without `su` logrotate refuses the whole glob and the unit exits 1
      # (the recurring "1 failed service(s)" briefing alert).
      su = "root users";
      create = "0664 root users";
    };
  };
}
