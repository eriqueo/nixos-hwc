# domains/alerts/parts/cli.nix
#
# hwc-alert CLI tool for sending alerts from command line
# Provides user-friendly interface to the alert system with logging

{ pkgs, lib, config }:

let
  cfg = config.hwc.alerts;
  webhookScripts = import ./slack-webhook.nix { inherit pkgs lib config; };
  logDir = "/var/log/hwc/alerts";

in
pkgs.writeScriptBin "hwc-alert" ''
  #!${pkgs.bash}/bin/bash
  set -euo pipefail

  # hwc-alert - Send alerts to Slack via n8n webhook
  #
  # Usage:
  #   hwc-alert <title> <message> [options]
  #   hwc-alert -t|--title <title> -m|--message <message> [options]
  #
  # Options:
  #   -t, --title <title>      Alert title (required)
  #   -m, --message <message>  Alert message (required)
  #   -s, --severity <level>   Severity: info, warning, critical (default: ${cfg.cli.defaultSeverity})
  #   -e, --endpoint <name>    Endpoint: system, backup, smartd, services (default: ${cfg.cli.defaultEndpoint})
  #   -f, --field <key=value>  Add custom field (can be repeated)
  #   --test                   Test mode: check webhook health without sending
  #   --dry-run                Show what would be sent without sending
  #   -h, --help               Show this help
  #
  # Examples:
  #   hwc-alert "Test Alert" "This is a test message"
  #   hwc-alert -t "Backup" -m "Backup completed" -s info -e backup
  #   hwc-alert "Build Failed" "NixOS rebuild failed" -s critical -f "exit_code=1"
  #   hwc-alert --test  # Check if webhook is reachable

  LOG_DIR="${logDir}"
  LOG_FILE="$LOG_DIR/cli.log"
  ${pkgs.coreutils}/bin/mkdir -p "$LOG_DIR"

  log() {
    echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] CLI: $1" >> "$LOG_FILE"
  }

  show_help() {
    ${pkgs.coreutils}/bin/cat << 'EOF'
hwc-alert - Send alerts to Slack via n8n webhook

Usage:
  hwc-alert <title> <message> [options]
  hwc-alert -t|--title <title> -m|--message <message> [options]

Options:
  -t, --title <title>      Alert title (required)
  -m, --message <message>  Alert message (required)
  -s, --severity <level>   Severity: info, warning, critical (default: ${cfg.cli.defaultSeverity})
  -e, --endpoint <name>    Endpoint: system, backup, smartd, services (default: ${cfg.cli.defaultEndpoint})
  -f, --field <key=value>  Add custom field (can be repeated)
  --test                   Test mode: check webhook health without sending
  --dry-run                Show what would be sent without sending
  --status                 Show recent alert activity
  -h, --help               Show this help

Severity Levels:
  info      - Informational (${cfg.severity.info})
  warning   - Attention needed (${cfg.severity.warning})
  critical  - Immediate action required (${cfg.severity.critical})

Endpoints:
  system    - General system alerts
  backup    - Backup notifications
  smartd    - Disk/SMART alerts
  services  - Service failure alerts

Log Files:
  ${logDir}/webhook.log       - All webhook attempts
  ${logDir}/failed-alerts.log - Failed alerts (for retry)
  ${logDir}/cli.log           - CLI usage log

Examples:
  hwc-alert "Test Alert" "This is a test message"
  hwc-alert -t "Backup" -m "Backup completed" -s info -e backup
  hwc-alert "Build Failed" "NixOS rebuild failed" -s critical -f "exit_code=1"
  hwc-alert --test  # Check if webhook is reachable
  hwc-alert --status  # Show recent alerts
EOF
  }

  show_status() {
    echo "=== HWC Alerts Status ==="
    echo ""
    echo "Log directory: $LOG_DIR"
    echo ""

    if [ -f "$LOG_DIR/webhook.log" ]; then
      echo "--- Recent webhook activity (last 10 lines) ---"
      ${pkgs.coreutils}/bin/tail -10 "$LOG_DIR/webhook.log"
      echo ""
    else
      echo "No webhook log found"
    fi

    if [ -f "$LOG_DIR/failed-alerts.log" ]; then
      FAILED_COUNT=$(${pkgs.coreutils}/bin/wc -l < "$LOG_DIR/failed-alerts.log" | ${pkgs.coreutils}/bin/tr -d ' ')
      echo "--- Failed alerts: $FAILED_COUNT entries ---"
      ${pkgs.coreutils}/bin/tail -5 "$LOG_DIR/failed-alerts.log"
      echo ""
    else
      echo "No failed alerts (good!)"
    fi

    echo "--- Webhook health check ---"
    ${webhookScripts.webhookHealthCheck}/bin/hwc-webhook-health && echo "Webhook endpoint is healthy" || echo "WARNING: Webhook endpoint unreachable"
  }

  # Default values
  TITLE=""
  MESSAGE=""
  SEVERITY="${cfg.cli.defaultSeverity}"
  ENDPOINT="${cfg.cli.defaultEndpoint}"
  EXTRA_FIELDS="{}"
  TEST_MODE=false
  DRY_RUN=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;
      --test)
        TEST_MODE=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --status)
        show_status
        exit 0
        ;;
      -t|--title)
        TITLE="$2"
        shift 2
        ;;
      -m|--message)
        MESSAGE="$2"
        shift 2
        ;;
      -s|--severity)
        SEVERITY="$2"
        shift 2
        ;;
      -e|--endpoint)
        ENDPOINT="$2"
        shift 2
        ;;
      -f|--field)
        # Parse key=value and add to extra fields
        KEY=$(echo "$2" | cut -d= -f1)
        VALUE=$(echo "$2" | cut -d= -f2-)
        EXTRA_FIELDS=$(echo "$EXTRA_FIELDS" | ${pkgs.jq}/bin/jq --arg k "$KEY" --arg v "$VALUE" '. + {($k): $v}')
        shift 2
        ;;
      -*)
        echo "Unknown option: $1" >&2
        show_help
        exit 1
        ;;
      *)
        # Positional arguments: first is title, second is message
        if [ -z "$TITLE" ]; then
          TITLE="$1"
        elif [ -z "$MESSAGE" ]; then
          MESSAGE="$1"
        else
          echo "Unexpected argument: $1" >&2
          exit 1
        fi
        shift
        ;;
    esac
  done

  # Test mode - just check webhook health
  if [ "$TEST_MODE" = true ]; then
    echo "Testing webhook endpoint connectivity..."
    if ${webhookScripts.webhookHealthCheck}/bin/hwc-webhook-health; then
      echo "SUCCESS: Webhook endpoint is reachable"
      echo ""
      echo "Sending test alert..."
      ${webhookScripts.webhookSender}/bin/hwc-webhook-send \
        system \
        "Test Alert" \
        "This is a test alert from hwc-alert --test" \
        info \
        '{"source": "cli-test"}'
      exit $?
    else
      echo "FAILED: Webhook endpoint is not reachable"
      echo "Check n8n status: systemctl status n8n"
      exit 1
    fi
  fi

  # Validate required fields
  if [ -z "$TITLE" ]; then
    echo "Error: Title is required" >&2
    show_help
    exit 1
  fi

  if [ -z "$MESSAGE" ]; then
    echo "Error: Message is required" >&2
    show_help
    exit 1
  fi

  # Validate severity
  case "$SEVERITY" in
    info|warning|critical)
      ;;
    *)
      echo "Error: Invalid severity '$SEVERITY'. Use: info, warning, critical" >&2
      exit 1
      ;;
  esac

  # Validate endpoint
  case "$ENDPOINT" in
    system|backup|smartd|services)
      ;;
    *)
      echo "Error: Invalid endpoint '$ENDPOINT'. Use: system, backup, smartd, services" >&2
      exit 1
      ;;
  esac

  # Add source field
  EXTRA_FIELDS=$(echo "$EXTRA_FIELDS" | ${pkgs.jq}/bin/jq '. + {source: "cli"}')

  # Dry run mode
  if [ "$DRY_RUN" = true ]; then
    echo "=== DRY RUN - Would send: ==="
    echo "Endpoint: $ENDPOINT"
    echo "Title: $TITLE"
    echo "Message: $MESSAGE"
    echo "Severity: $SEVERITY"
    echo "Extra fields: $EXTRA_FIELDS"
    exit 0
  fi

  log "Sending alert: [$SEVERITY] $TITLE"

  # Send the alert
  ${webhookScripts.webhookSender}/bin/hwc-webhook-send \
    "$ENDPOINT" \
    "$TITLE" \
    "$MESSAGE" \
    "$SEVERITY" \
    "$EXTRA_FIELDS"
''
