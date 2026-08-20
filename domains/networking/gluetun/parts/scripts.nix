# domains/networking/gluetun/parts/scripts.nix
#
# Per-instance VPN health monitor.
#
# The version this replaces restarted gluetun every 15 minutes for 33 hours
# against a peer that was never coming back, and fired 43 identical alerts into
# #hwc-alerts in 24 hours — one per check, all saying the same thing. Nobody
# acted, because there was nothing in the stream to act ON: no transition, no
# escalation, no give-up. Two changes address that class of failure rather than
# the incident:
#
#   * Alert on TRANSITIONS, never on state. healthy→degraded, degraded→failed
#     and any→healthy each emit exactly once. A 33-hour outage is 2 messages.
#   * Bounded retry. Restart attempts back off 15m→30m→1h→2h→4h (capped), and
#     after `escalateAfterRestarts` failed restarts the instance is declared
#     `failed` and paged once. It keeps trying at the cap after that — a
#     transient drop must still self-heal — but it stops shouting.
#
# Sustained degradation also lands in the morning briefing via status.json:
# #hwc-alerts is where an alert goes, and the briefing is where Eric actually
# looks the next morning.

{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.networking.gluetun;
  instances = lib.filterAttrs (_: i: i.enable && i.healthCheck.enable) cfg.instances;
  stateDir = name: "${cfg.stateRoot}/${name}";

  healthCheckScript = name: i:
    let hc = i.healthCheck; in
    pkgs.writeShellScript "${name}-health-check" ''
      set -euo pipefail

      API="http://127.0.0.1:${toString i.controlPort}"
      STATE_DIR="${stateDir name}"
      STATUS="$STATE_DIR/status.json"
      NOTIFY_URL="${if hc.notifyUrl != null then hc.notifyUrl else ""}"
      ESCALATE_AFTER=${toString hc.escalateAfterRestarts}
      FAILURES_BEFORE_RESTART=${toString hc.failuresBeforeRestart}
      BACKOFF=(${lib.concatStringsSep " " (map toString hc.backoffSteps)})
      NOW=$(date +%s)

      CURL="${pkgs.curl}/bin/curl"
      JQ="${pkgs.jq}/bin/jq"
      SYSTEMCTL="${pkgs.systemd}/bin/systemctl"

      mkdir -p "$STATE_DIR"

      # Alert via hwc-notify. Fail-soft: a down dispatcher must never break the
      # check itself, but a dropped alert says so in the journal.
      notify() { # $1=priority $2=title $3=body
        [ -n "$NOTIFY_URL" ] || return 0
        "$JQ" -nc --arg t "$2" --arg b "$3" --argjson p "$1" \
          '{topic:"monitoring", source:"gluetun-health", title:$t, body:$b, priority:$p, tags:["vpn","${name}"]}' \
          | "$CURL" -fsS --max-time 8 -X POST -H 'content-type: application/json' \
              -d @- "$NOTIFY_URL/notify" >/dev/null 2>&1 \
          || echo "WARN: hwc-notify unreachable (alert dropped)"
      }

      # ---- prior state (absent file = healthy, first run) -------------------
      PREV_STATE=healthy; FAILURES=0; RESTARTS=0; DEGRADED_SINCE=0; LAST_RESTART=0
      if [ -f "$STATUS" ]; then
        PREV_STATE=$("$JQ" -r '.state // "healthy"' "$STATUS" 2>/dev/null || echo healthy)
        FAILURES=$("$JQ" -r '.consecutive_failures // 0' "$STATUS" 2>/dev/null || echo 0)
        RESTARTS=$("$JQ" -r '.restart_count // 0' "$STATUS" 2>/dev/null || echo 0)
        DEGRADED_SINCE=$("$JQ" -r '.degraded_since // 0' "$STATUS" 2>/dev/null || echo 0)
        LAST_RESTART=$("$JQ" -r '.last_restart_at // 0' "$STATUS" 2>/dev/null || echo 0)
      fi

      # ---- probe -----------------------------------------------------------
      # Authoritative signals only: what the control server already reports, not
      # a proxy for it. The 2026-08-18 outage had a REACHABLE control API the
      # whole time — "the container is up" was never the question.
      REASON=""
      PORT=0

      if ! "$CURL" -sf --max-time 10 "$API/v1/portforward" >/dev/null 2>&1; then
        REASON="control API unreachable"
      else
        PUBIP=$("$CURL" -sf --max-time 10 "$API/v1/publicip/ip" | "$JQ" -r '.public_ip // empty' 2>/dev/null || true)
        PORT=$("$CURL" -sf --max-time 10 "$API/v1/portforward" | "$JQ" -r '.port // 0' 2>/dev/null || echo 0)
        [ -n "$PORT" ] || PORT=0

        if [ -z "$PUBIP" ]; then
          # Tunnel is up but carrying nothing. This is the check that catches
          # "wg show reads 0 B received" while the API answers fine.
          REASON="tunnel has no public IP (not passing traffic)"
        ${lib.optionalString i.portForwarding.enable ''
        elif [ "$PORT" = "0" ]; then
          REASON="no forwarded port"
        ''}${lib.optionalString (i.portForwarding.syncTo == "slskd") ''
        elif ! ${pkgs.gnugrep}/bin/grep -q "listen_port: $PORT" /etc/slskd/slskd.yml 2>/dev/null; then
          # Drift between the forwarded port and the port slskd actually listens
          # on is invisible from outside: downloads keep working and inbound
          # silently stops. Treat it as unhealthy so it self-heals.
          REASON="slskd listen_port does not match forwarded port $PORT"
        ''}
        fi
      fi

      # ---- state machine ---------------------------------------------------
      STATE="$PREV_STATE"
      DID_RESTART=0

      restart_now() {
        echo "Restarting podman-${name} (attempt $((RESTARTS + 1)))"
        "$SYSTEMCTL" restart podman-${name}.service || true
        RESTARTS=$((RESTARTS + 1))
        LAST_RESTART=$NOW
        DID_RESTART=1
      }

      # Minimum seconds before the next restart, from the backoff ladder.
      backoff_for() { # $1 = restarts already made
        local idx="$1"
        local last=$(( ''${#BACKOFF[@]} - 1 ))
        [ "$idx" -gt "$last" ] && idx="$last"
        echo "''${BACKOFF[$idx]}"
      }

      if [ -z "$REASON" ]; then
        FAILURES=0
        if [ "$PREV_STATE" != "healthy" ]; then
          DOWN_FOR=$(( NOW - DEGRADED_SINCE ))
          notify 3 "VPN ${name} recovered" \
            "Healthy again after $((DOWN_FOR / 60))m and $RESTARTS restart(s). Forwarded port: $PORT."
          echo "RECOVERED after $((DOWN_FOR / 60))m / $RESTARTS restarts (port $PORT)"
        else
          echo "OK: port $PORT"
        fi
        STATE=healthy; RESTARTS=0; DEGRADED_SINCE=0; LAST_RESTART=0
      else
        FAILURES=$((FAILURES + 1))
        echo "FAIL ($FAILURES): $REASON"

        case "$PREV_STATE" in
          healthy)
            if [ "$FAILURES" -ge "$FAILURES_BEFORE_RESTART" ]; then
              STATE=degraded
              DEGRADED_SINCE=$NOW
              notify 2 "VPN ${name} degraded" \
                "$REASON — failed $FAILURES consecutive checks. Auto-restarting with backoff; the next message is either recovery or give-up."
              restart_now
            fi
            ;;
          degraded|failed)
            WAIT=$(backoff_for "$RESTARTS")
            if [ $(( NOW - LAST_RESTART )) -ge "$WAIT" ]; then
              restart_now
              if [ "$PREV_STATE" = "degraded" ] && [ "$RESTARTS" -gt "$ESCALATE_AFTER" ]; then
                STATE=failed
                notify 1 "VPN ${name} — auto-recovery exhausted" \
                  "$REASON — still down after $RESTARTS restarts over $(( (NOW - DEGRADED_SINCE) / 60 ))m. Automation cannot fix this; a human needs to look. Most likely a dead pinned peer: check 'podman exec ${name} wg show' for 0 B received, then re-point hwc.networking.gluetun.instances.${name}.wireguard.*."
              fi
            else
              echo "Backing off: next restart in $(( WAIT - (NOW - LAST_RESTART) ))s (state $PREV_STATE)"
            fi
            ;;
        esac
      fi

      # ---- publish status (read by the morning briefing) --------------------
      "$JQ" -nc \
        --arg instance "${name}" \
        --arg state "$STATE" \
        --arg reason "$REASON" \
        --argjson port "$PORT" \
        --argjson failures "$FAILURES" \
        --argjson restarts "$RESTARTS" \
        --argjson degraded_since "$DEGRADED_SINCE" \
        --argjson last_restart_at "$LAST_RESTART" \
        --argjson last_check "$NOW" \
        --argjson did_restart "$DID_RESTART" \
        '{instance:$instance, state:$state, reason:$reason, forwarded_port:$port,
          consecutive_failures:$failures, restart_count:$restarts,
          degraded_since:$degraded_since, last_restart_at:$last_restart_at,
          last_check:$last_check, restarted_this_check:($did_restart == 1)}' \
        > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"
    '';
in
{
  # Plain attrset, for the same reason as parts/config.nix: a top-level mkIf or
  # mkMerge over config-derived contents is forced before config is fixed.
  config = {
      # State dirs are created in parts/config.nix. The old singleton location
      # goes away here: what it held (a failure counter) is derived state that
      # the first check rebuilds, so the migration is a delete, not a move.
      # `R`, not `R!`: `R!` is boot-only, while plain `R` also fires on any
      # `systemd-tmpfiles --remove` run. Neither fires on a plain switch —
      # NixOS activation runs `--create`, not `--remove` — so the honest
      # statement is "gone by next boot, or immediately if you run
      # `systemd-tmpfiles --remove`", which is what was done on hwc-server.
      systemd.tmpfiles.rules =
        lib.optionals (instances != {}) [ "R /var/lib/hwc/gluetun-health - - - - -" ];

      systemd.timers = lib.mapAttrs' (name: i:
        lib.nameValuePair "${name}-health-check" {
          description = "Gluetun ${name} health check timer";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "2min";
            OnUnitActiveSec = "${toString i.healthCheck.checkInterval}s";
            Persistent = false;
          };
        }) instances;

      systemd.services = lib.mapAttrs' (name: i:
        lib.nameValuePair "${name}-health-check" {
          description = "Gluetun ${name} VPN + port forwarding health check";
          after = [ "podman-${name}.service" "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = healthCheckScript name i;
            User = "root";  # needs to restart podman-${name}.service
            PrivateTmp = true;
            NoNewPrivileges = true;
          };
        }) instances;
  };
}
