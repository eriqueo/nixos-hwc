# domains/notifications/canary.nix
#
# Delivery canary — a deadman probe for the notification path.
#
# The premortem's headline failure was silent: hwc-notify returns a 207
# multi-status when one adapter dies, records it to a SQLite audit log
# nobody reads, and a real critical quietly never arrives. This canary
# turns that invisible failure loud. On a timer it POSTs one synthetic
# notification routed (via the `canary` topic) to BOTH a Discord channel
# and the SMTP adapter, then inspects the dispatch result:
#
#   - all adapters delivered      → succeed quietly (the canary message
#                                    itself is the human-visible heartbeat)
#   - any adapter failed / down   → exit non-zero (surfaces in
#                                    `systemctl --failed` + journal ERROR),
#                                    drop a sentinel file, and best-effort
#                                    escalate. The sentinel + failed unit
#                                    are independent of the very delivery
#                                    path under test.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.notifications.notify;
  canary = config.hwc.notifications.canary;
  base = "http://${cfg.bindAddr}:${toString cfg.port}";
  sentinel = "/var/log/hwc/notifications/canary-FAILED";

  canaryScript = pkgs.writeShellApplication {
    name = "hwc-notify-canary";
    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.coreutils pkgs.util-linux ];
    text = ''
      set -uo pipefail
      base="${base}"
      sentinel="${sentinel}"
      ts="$(date -Iseconds)"

      payload=$(jq -nc --arg ts "$ts" '{
        topic: "canary",
        title: "[canary] notification delivery probe",
        body: ("Synthetic delivery probe at " + $ts + ". If you are reading this, Discord + SMTP delivery are both alive. This fires on a timer; no action needed."),
        priority: 3,
        source: "delivery-canary",
        tags: ["canary"]
      }')

      # Capture body + HTTP status. --max-time guards a hung dispatcher.
      resp=$(curl -sS --max-time 30 -w '\n%{http_code}' -X POST \
        -H 'content-type: application/json' -d "$payload" "$base/notify" 2>&1) || {
          echo "canary: dispatcher unreachable at $base/notify" >&2
          date -Iseconds > "$sentinel" 2>/dev/null || true
          echo "$base/notify unreachable" >> "$sentinel" 2>/dev/null || true
          exit 1
        }

      code=$(printf '%s' "$resp" | tail -n1)
      body=$(printf '%s' "$resp" | head -n -1)

      attempted=$(printf '%s' "$body" | jq -r '.attempted // 0' 2>/dev/null || echo 0)
      succeeded=$(printf '%s' "$body" | jq -r '.succeeded // 0' 2>/dev/null || echo 0)

      if [ "$code" = "200" ] && [ "$attempted" -gt 0 ] && [ "$succeeded" = "$attempted" ]; then
        # All adapters delivered. Clear any stale sentinel and exit clean.
        rm -f "$sentinel" 2>/dev/null || true
        echo "canary OK: $succeeded/$attempted adapters delivered (HTTP $code)"
        exit 0
      fi

      # Delivery degraded or failed — make it loud and independent of the
      # delivery path itself.
      failed=$(printf '%s' "$body" \
        | jq -r '[.results[]? | select(.ok==false) | .channelId] | join(", ")' 2>/dev/null || echo "unknown")
      msg="canary FAILED: $succeeded/$attempted delivered (HTTP $code); down: ''${failed:-unknown}"
      echo "$msg" >&2
      { date -Iseconds; echo "$msg"; printf '%s\n' "$body"; } > "$sentinel" 2>/dev/null || true

      # Best-effort human escalation. May itself fail if the same adapter is
      # down; the non-zero exit + sentinel are the reliable signals.
      echo "CANARY: notification delivery degraded — $msg" | wall 2>/dev/null || true
      exit 1
    '';
  };

in
{
  options.hwc.notifications.canary = {
    enable = lib.mkEnableOption "hwc-notify delivery canary (deadman probe over Discord + SMTP)";

    interval = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = ''
        systemd OnCalendar expression for the canary cadence. Default
        "daily" — one heartbeat notification per day proving the Discord
        and SMTP (critical email) paths are both alive.
      '';
    };
  };

  config = lib.mkIf (config.hwc.notifications.enable && canary.enable) {
    environment.systemPackages = [ canaryScript ];

    systemd.services.hwc-notify-canary = {
      description = "hwc-notify delivery canary (Discord + SMTP deadman probe)";
      after = [ "hwc-notify.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${canaryScript}/bin/hwc-notify-canary";
        User = lib.mkForce "eric";
        Group = "users";
      };
    };

    systemd.timers.hwc-notify-canary = {
      description = "hwc-notify delivery canary timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = canary.interval;
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    };
  };
}
