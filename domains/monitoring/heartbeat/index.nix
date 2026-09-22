# domains/monitoring/heartbeat/index.nix
#
# Outbound heartbeat to an external dead-man's switch (healthchecks.io).
#
# Every other alert path on this host delivers through hwc-notify, from this
# host, over this host's internet link. None of them can report that the host
# is off, that the internet is down, or that hwc-notify itself is dead
# (domains/monitoring/alerts/index.nix, "NOT A DEADMAN"). This unit is that
# watcher: it pings an outside service on a timer, and the outside service
# alerts Eric when the pings STOP. Silence is the signal, so it keeps working
# when everything here has failed.
#
# NAMESPACE: hwc.monitoring.heartbeat.*
#
# DEPENDENCIES:
#   - agenix secret holding the check's ping URL (pingUrlFile)
#
# USED BY:
#   - machines/server/config.nix

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.monitoring.heartbeat;

  pingScript = pkgs.writeShellApplication {
    name = "hwc-heartbeat";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      # --retry: at most 3 retries with curl's own exponential backoff, capped
      # at 60s total. A missed ping is harmless; the check's grace period
      # absorbs it. Pinging is idempotent, so retrying is safe.
      curl -fsS --max-time 10 --retry 3 --retry-max-time 60 \
        --output /dev/null "$(cat ${lib.escapeShellArg cfg.pingUrlFile})"
    '';
  };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.monitoring.heartbeat = {
    enable = lib.mkEnableOption "outbound heartbeat to an external dead-man's switch";

    pingUrlFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        File holding the check's ping URL (https://hc-ping.com/<uuid>). The
        URL is a credential: anyone holding it can keep the check green.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "*:0/5";
      description = ''
        systemd OnCalendar for the ping. Must match the check's period on the
        healthchecks.io side; set its grace time to at least twice this.
      '';
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    systemd.services.hwc-heartbeat = {
      description = "Ping the external dead-man's switch";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pingScript}/bin/hwc-heartbeat";
        User = lib.mkForce "eric";
        Group = "users";
        SupplementaryGroups = [ "secrets" ];
      };
    };

    systemd.timers.hwc-heartbeat = {
      description = "Heartbeat ping timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.interval;
        # No Persistent= and no catch-up: a ping only means "alive now".
        AccuracySec = "30s";
      };
    };

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = lib.hasPrefix "/run/agenix/" (toString cfg.pingUrlFile);
        message = "hwc.monitoring.heartbeat.pingUrlFile must be an agenix secret path (/run/agenix/...); the ping URL is a credential.";
      }
    ];
  };
}
