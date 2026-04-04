# domains/notifications/health.nix
#
# Webhook health check service and timer
#
# Periodically checks that the n8n webhook endpoint is reachable.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.notifications;
  webhookScripts = import ./send/slack-webhook.nix { inherit pkgs lib config; };
in
{
  config = lib.mkIf cfg.enable {
    # =======================================================================
    # WEBHOOK HEALTH CHECK SERVICE
    # =======================================================================
    systemd.services.hwc-webhook-health = {
      description = "HWC webhook endpoint health check";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${webhookScripts.webhookHealthCheck}/bin/hwc-webhook-health";
        User = "root";
      };
    };

    # =======================================================================
    # WEBHOOK HEALTH CHECK TIMER
    # =======================================================================
    systemd.timers.hwc-webhook-health = {
      description = "HWC webhook health check timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = "*:0/15";  # Every 15 minutes
        Persistent = false;
        RandomizedDelaySec = "1min";
      };
    };
  };
}
