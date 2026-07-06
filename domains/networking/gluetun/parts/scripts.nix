# domains/networking/gluetun/parts/scripts.nix
#
# Gluetun VPN health check — monitors port forwarding and auto-restarts on failure.

{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.networking.gluetun;
  hcCfg = cfg.healthCheck;

  healthCheckScript = pkgs.writeShellScript "gluetun-health-check" ''
    set -euo pipefail

    GLUETUN_API="http://127.0.0.1:8000"
    STATE_FILE="/var/lib/hwc/gluetun-health/failure-count"
    RECOVERY_FILE="/var/lib/hwc/gluetun-health/last-recovery"
    CHECK_INTERVAL=${toString hcCfg.checkInterval}
    FAILURES_BEFORE_RESTART=${toString hcCfg.failuresBeforeRestart}
    NOTIFY_URL="${if hcCfg.notifyUrl != null then hcCfg.notifyUrl else ""}"

    # Alert via hwc-notify (replaced gotify 2026-07-06). Fail-soft: a down or
    # slow dispatcher must never break the health check itself.
    notify() { # $1=priority $2=title $3=body
      [ -n "$NOTIFY_URL" ] || return 0
      ${pkgs.jq}/bin/jq -nc --arg t "$2" --arg b "$3" --argjson p "$1"         '{topic:"monitoring", source:"gluetun-health", title:$t, body:$b, priority:$p, tags:["vpn"]}'         | ${pkgs.curl}/bin/curl -fsS --max-time 8 -X POST -H 'content-type: application/json'             -d @- "$NOTIFY_URL/notify" >/dev/null 2>&1 || echo "WARN: hwc-notify unreachable (alert dropped)"
    }

    mkdir -p /var/lib/hwc/gluetun-health

    # Read current failure count
    FAILURES=0
    if [ -f "$STATE_FILE" ]; then
      FAILURES=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
    fi

    # Check 1: Can we reach the gluetun control API?
    if ! ${pkgs.curl}/bin/curl -sf --max-time 10 "$GLUETUN_API/v1/portforward" >/dev/null 2>&1; then
      FAILURES=$((FAILURES + 1))
      echo "$FAILURES" > "$STATE_FILE"
      echo "FAIL ($FAILURES): Gluetun API unreachable"

      if [ "$FAILURES" -ge "$FAILURES_BEFORE_RESTART" ]; then
        echo "Restarting gluetun after $FAILURES consecutive failures..."
        notify 2 "gluetun auto-restart (API unreachable)" "Control API failed $FAILURES consecutive checks; restarting podman-gluetun."
        ${pkgs.systemd}/bin/systemctl restart podman-gluetun.service
        echo "0" > "$STATE_FILE"
        date -Iseconds > "$RECOVERY_FILE"
      fi
      exit 0
    fi

    # Check 2: Is port forwarding active (non-zero)?
    FORWARDED_PORT=$(${pkgs.curl}/bin/curl -sf --max-time 10 "$GLUETUN_API/v1/portforward" | ${pkgs.jq}/bin/jq -r '.port // 0')

    if [ "$FORWARDED_PORT" = "0" ] || [ -z "$FORWARDED_PORT" ]; then
      FAILURES=$((FAILURES + 1))
      echo "$FAILURES" > "$STATE_FILE"
      echo "FAIL ($FAILURES): Port forwarding is 0 (no forwarded port)"

      if [ "$FAILURES" -ge "$FAILURES_BEFORE_RESTART" ]; then
        echo "Restarting gluetun after $FAILURES consecutive port forwarding failures..."
        notify 2 "gluetun auto-restart (port forwarding lost)" "Forwarded port was 0 for $FAILURES consecutive checks; restarting podman-gluetun."
        ${pkgs.systemd}/bin/systemctl restart podman-gluetun.service
        echo "0" > "$STATE_FILE"
        date -Iseconds > "$RECOVERY_FILE"
      fi
      exit 0
    fi

    # All checks passed — reset failure counter
    if [ "$FAILURES" -gt 0 ]; then
      echo "RECOVERED after $FAILURES failures (port: $FORWARDED_PORT)"
      notify 3 "gluetun recovered" "VPN healthy again after $FAILURES failed checks (forwarded port: $FORWARDED_PORT)."
      echo "0" > "$STATE_FILE"
    else
      echo "OK: port $FORWARDED_PORT"
    fi
  '';
in
{
  config = lib.mkIf (cfg.enable && hcCfg.enable) {
    # State directory for failure tracking
    systemd.tmpfiles.rules = [
      "d /var/lib/hwc/gluetun-health 0755 root root -"
    ];

    # Health check timer — runs every checkInterval seconds
    systemd.timers.gluetun-health-check = {
      description = "Gluetun VPN health check timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "${toString hcCfg.checkInterval}s";
        Persistent = false;
      };
    };

    # Health check service — oneshot
    systemd.services.gluetun-health-check = {
      description = "Gluetun VPN + port forwarding health check";
      after = [ "podman-gluetun.service" "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = healthCheckScript;
        # Needs root to restart podman-gluetun.service
        User = "root";

        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
  };
}
