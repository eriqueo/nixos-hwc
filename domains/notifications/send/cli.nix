# domains/notifications/send/cli.nix
#
# hwc-alert — human/script front-end onto the hwc-notify core.
#
# One command = one intent: "send an alert". It parses friendly args
# (title/message/severity/endpoint/fields) and POSTs the native
# NotificationInput shape to the loopback dispatcher at :11600/notify.
# The dispatcher owns routing, fan-out, audit, and circuit-breaking —
# this shell never talks to Slack/gotify/n8n. It is the sibling of the
# machine front-end (the HTTP port itself).
#
# Severity → priority uses hwc-notify's convention (critical→1 … info→3);
# endpoint → source; -f k=v → context. topic is "monitoring" so alerts
# route to #hwc-alerts (and criticals fan out to email via p1-fanout).

{ pkgs, lib, config }:

let
  cliCfg = config.hwc.notifications.send.cli;
  notifyCfg = config.hwc.notifications.notify;
  base = "http://${notifyCfg.bindAddr}:${toString notifyCfg.port}";
  logDir = "/var/log/hwc/notifications";

in
pkgs.writeShellApplication {
  name = "hwc-alert";
  runtimeInputs = [ pkgs.curl pkgs.jq pkgs.coreutils ];
  text = ''
    set -euo pipefail

    # hwc-alert - Send alerts to the hwc-notify dispatcher (:11600/notify)
    #
    # Usage:
    #   hwc-alert <title> <message> [options]
    #   hwc-alert -t|--title <title> -m|--message <message> [options]
    #
    # Options:
    #   -t, --title <title>      Alert title (required)
    #   -m, --message <message>  Alert message (required)
    #   -s, --severity <level>   Severity: info, warning, critical (default: ${cliCfg.defaultSeverity})
    #   -e, --endpoint <name>    Source tag: system, backup, smartd, services (default: ${cliCfg.defaultEndpoint})
    #   -f, --field <key=value>  Add context field (can be repeated)
    #   --test                   Send a test notification through the dispatcher
    #   --dry-run                Show the payload without sending
    #   --status                 Show recent dispatch activity
    #   -h, --help               Show this help

    BASE="${base}"
    LOG_DIR="${logDir}"
    LOG_FILE="$LOG_DIR/cli.log"

    # Logging is a convenience, never a gate: hwc-alert runs both as root
    # (systemd notifiers) and as an unprivileged user (interactive), so a
    # log write that fails on permissions must not abort the send. The
    # dispatcher's SQLite audit log is the authoritative record.
    log() {
      { mkdir -p "$LOG_DIR" && echo "[$(date '+%Y-%m-%d %H:%M:%S')] CLI: $1" >> "$LOG_FILE"; } 2>/dev/null || true
    }

    show_help() {
      cat << 'EOF'
hwc-alert - Send alerts to the hwc-notify dispatcher (:11600/notify)

Usage:
  hwc-alert <title> <message> [options]
  hwc-alert -t|--title <title> -m|--message <message> [options]

Options:
  -t, --title <title>      Alert title (required)
  -m, --message <message>  Alert message (required)
  -s, --severity <level>   Severity: info, warning, critical (default: ${cliCfg.defaultSeverity})
  -e, --endpoint <name>    Source tag: system, backup, smartd, services (default: ${cliCfg.defaultEndpoint})
  -f, --field <key=value>  Add context field (can be repeated)
  --test                   Send a test notification through the dispatcher
  --dry-run                Show the payload without sending
  --status                 Show recent dispatch activity
  -h, --help               Show this help

Severity → priority (hwc-notify convention):
  critical  → 1   (fans out to #hwc-alerts, #hwc-leads, and email via p1-fanout)
  warning   → 2
  info      → 3

Endpoints (become the notification 'source'):
  system    - General system alerts
  backup    - Backup notifications
  smartd    - Disk/SMART alerts
  services  - Service failure alerts
EOF
    }

    # Map endpoint → source; validate against the known set.
    valid_endpoint() {
      case "$1" in
        system|backup|smartd|services) return 0 ;;
        *) return 1 ;;
      esac
    }

    # Map severity → hwc-notify priority.
    severity_to_priority() {
      case "$1" in
        critical) echo 1 ;;
        warning)  echo 2 ;;
        info)     echo 3 ;;
        *)        echo 3 ;;
      esac
    }

    # Build the native NotificationInput payload and POST it.
    #   $1 title  $2 message  $3 severity  $4 endpoint(source)  $5 context-json
    send_notify() {
      local title="$1" message="$2" severity="$3" source="$4" context="$5"
      local priority
      priority=$(severity_to_priority "$severity")
      local payload
      payload=$(jq -nc \
        --arg title "$title" \
        --arg body "$message" \
        --arg source "$source" \
        --argjson priority "$priority" \
        --argjson context "$context" \
        '{topic: "monitoring", title: $title, body: $body, priority: $priority,
          source: $source, tags: ["severity:\($priority|tostring)"], context: $context}')
      curl -fsS --max-time 15 -X POST -H 'content-type: application/json' \
        -d "$payload" "$BASE/notify"
    }

    show_status() {
      echo "=== hwc-notify recent activity ==="
      if curl -fsS --max-time 10 "$BASE/audit/recent?limit=10" 2>/dev/null | jq -e . >/dev/null 2>&1; then
        curl -fsS --max-time 10 "$BASE/audit/recent?limit=10" \
          | jq -r '.rows[]? | "\(.receivedAt)  [\(.priority)] \(.title)  → \(.matchedRule)"'
      else
        echo "WARNING: dispatcher unreachable at $BASE/audit/recent"
      fi
      echo ""
      if [ -f "$LOG_FILE" ]; then
        echo "--- CLI log (last 5) ---"
        tail -5 "$LOG_FILE"
      fi
    }

    # Defaults
    TITLE=""
    MESSAGE=""
    SEVERITY="${cliCfg.defaultSeverity}"
    ENDPOINT="${cliCfg.defaultEndpoint}"
    CONTEXT="{}"
    TEST_MODE=false
    DRY_RUN=false

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -h|--help)  show_help; exit 0 ;;
        --test)     TEST_MODE=true; shift ;;
        --dry-run)  DRY_RUN=true; shift ;;
        --status)   show_status; exit 0 ;;
        -t|--title)    TITLE="$2"; shift 2 ;;
        -m|--message)  MESSAGE="$2"; shift 2 ;;
        -s|--severity) SEVERITY="$2"; shift 2 ;;
        -e|--endpoint) ENDPOINT="$2"; shift 2 ;;
        -f|--field)
          KEY=$(echo "$2" | cut -d= -f1)
          VALUE=$(echo "$2" | cut -d= -f2-)
          CONTEXT=$(echo "$CONTEXT" | jq -c --arg k "$KEY" --arg v "$VALUE" '. + {($k): $v}')
          shift 2 ;;
        -*) echo "Unknown option: $1" >&2; show_help; exit 1 ;;
        *)
          if [ -z "$TITLE" ]; then TITLE="$1"
          elif [ -z "$MESSAGE" ]; then MESSAGE="$1"
          else echo "Unexpected argument: $1" >&2; exit 1
          fi
          shift ;;
      esac
    done

    # Test mode: probe /health then send a canned notification.
    if [ "$TEST_MODE" = true ]; then
      echo "Checking dispatcher health at $BASE/health ..."
      if curl -fsS --max-time 10 "$BASE/health" >/dev/null 2>&1; then
        echo "SUCCESS: dispatcher reachable. Sending test notification..."
        send_notify "Test Alert" "This is a test alert from hwc-alert --test" info system "{}" | jq
        exit $?
      else
        echo "FAILED: dispatcher unreachable at $BASE/health"
        echo "Check service: systemctl status hwc-notify"
        exit 1
      fi
    fi

    # Validate required fields
    [ -z "$TITLE" ]   && { echo "Error: Title is required" >&2;   show_help; exit 1; }
    [ -z "$MESSAGE" ] && { echo "Error: Message is required" >&2; show_help; exit 1; }

    case "$SEVERITY" in
      info|warning|critical) ;;
      *) echo "Error: Invalid severity '$SEVERITY'. Use: info, warning, critical" >&2; exit 1 ;;
    esac

    if ! valid_endpoint "$ENDPOINT"; then
      echo "Error: Invalid endpoint '$ENDPOINT'. Use: system, backup, smartd, services" >&2
      exit 1
    fi

    if [ "$DRY_RUN" = true ]; then
      echo "=== DRY RUN - would POST to $BASE/notify ==="
      echo "Title:    $TITLE"
      echo "Message:  $MESSAGE"
      echo "Severity: $SEVERITY (priority $(severity_to_priority "$SEVERITY"))"
      echo "Source:   $ENDPOINT"
      echo "Context:  $CONTEXT"
      exit 0
    fi

    log "Sending alert: [$SEVERITY] $TITLE"

    if send_notify "$TITLE" "$MESSAGE" "$SEVERITY" "$ENDPOINT" "$CONTEXT" >/dev/null; then
      echo "Alert sent: $TITLE ($SEVERITY)"
    else
      log "FAILED to send: [$SEVERITY] $TITLE"
      echo "ERROR: dispatcher POST failed for: $TITLE" >&2
      # Critical alerts get a wall message as last resort.
      if [ "$SEVERITY" = "critical" ]; then
        echo "CRITICAL ALERT: $TITLE - $MESSAGE" | ${pkgs.util-linux}/bin/wall 2>/dev/null || true
      fi
      exit 1
    fi
  '';
}
