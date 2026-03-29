# domains/automation/gotify/index.nix
#
# Gotify — Centralized notification system for cross-machine and cross-service alerts.
# Provides a reusable CLI tool (hwc-gotify-send) that can be called from backup scripts,
# systemd services, or any other component that needs to send notifications.
#
# NAMESPACE: hwc.automation.gotify.*

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.automation.gotify;

  # Build the hwc-gotify-send CLI tool
  gotifySendScript = pkgs.writeScriptBin "hwc-gotify-send" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # Configuration from NixOS module
    GOTIFY_SERVER="${cfg.serverUrl}"
    DEFAULT_TOKEN_FILE="${if cfg.defaultTokenFile != null then cfg.defaultTokenFile else ""}"
    DEFAULT_PRIORITY="${if cfg.defaultPriority != null then toString cfg.defaultPriority else ""}"
    HOST_TAG_ENABLED="${if cfg.hostTag then "true" else "false"}"

    # Get hostname for tagging
    HOSTNAME="$(${pkgs.nettools}/bin/hostname)"

    # Usage information
    usage() {
      cat <<EOF
Usage: hwc-gotify-send [OPTIONS] <title> <message>

Send notifications via gotify server.

Arguments:
  <title>      Notification title
  <message>    Notification message body

Options:
  --token-file PATH   Path to file containing gotify app token (overrides default)
  --priority LEVEL    Priority (0=min, 5=normal, 10=max)
  --help, -h          Show this help message

Examples:
  hwc-gotify-send "Backup Success" "All files backed up"
  hwc-gotify-send --priority 10 "Critical" "System down"
  hwc-gotify-send --token-file /run/agenix/gotify-token-backup "Backup Done" "Details..."

Configuration:
  Server:           $GOTIFY_SERVER
  Default Token:    ''${DEFAULT_TOKEN_FILE:-<none>}
  Default Priority: ''${DEFAULT_PRIORITY:-5}
  Host Tagging:     $HOST_TAG_ENABLED
EOF
      exit 0
    }

    # Error logging
    log_error() {
      echo "ERROR: $1" >&2
    }

    # Parse command-line arguments
    TOKEN_FILE_OVERRIDE=""
    EXTRA_PRIORITY=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --help|-h)
          usage
          ;;
        --token-file)
          shift
          TOKEN_FILE_OVERRIDE="$1"
          shift
          ;;
        --priority)
          shift
          EXTRA_PRIORITY="$1"
          shift
          ;;
        -*)
          log_error "Unknown option: $1"
          usage
          ;;
        *)
          break
          ;;
      esac
    done

    # Validate required arguments
    if [[ $# -lt 2 ]]; then
      log_error "Missing required arguments"
      echo "" >&2
      usage
    fi

    TITLE="$1"
    MESSAGE="$2"

    # Determine token file
    TOKEN_FILE="''${TOKEN_FILE_OVERRIDE:-$DEFAULT_TOKEN_FILE}"
    if [[ -z "$TOKEN_FILE" ]]; then
      log_error "No token file specified and no default token file configured"
      exit 1
    fi
    if [[ ! -f "$TOKEN_FILE" ]]; then
      log_error "Token file does not exist: $TOKEN_FILE"
      exit 1
    fi

    TOKEN=$(${pkgs.coreutils}/bin/cat "$TOKEN_FILE" | ${pkgs.coreutils}/bin/tr -d '[:space:]')

    # Build the gotify URL
    GOTIFY_URL="$GOTIFY_SERVER/message?token=$TOKEN"

    # Determine priority (command-line overrides default)
    FINAL_PRIORITY="$EXTRA_PRIORITY"
    if [[ -z "$FINAL_PRIORITY" && -n "$DEFAULT_PRIORITY" ]]; then
      FINAL_PRIORITY="$DEFAULT_PRIORITY"
    fi
    if [[ -z "$FINAL_PRIORITY" ]]; then
      FINAL_PRIORITY="5"
    fi

    # Add host tag to message if enabled
    FINAL_MESSAGE="$MESSAGE"
    if [[ "$HOST_TAG_ENABLED" == "true" ]]; then
      FINAL_MESSAGE="[host: $HOSTNAME] $MESSAGE"
    fi

    # Build JSON payload
    JSON_PAYLOAD=$(${pkgs.jq}/bin/jq -nc \
      --arg title "$TITLE" \
      --arg message "$FINAL_MESSAGE" \
      --argjson priority "$FINAL_PRIORITY" \
      '{"title": $title, "message": $message, "priority": $priority}')

    # Send the notification
    if ${pkgs.curl}/bin/curl -fsSL \
      -H "Content-Type: application/json" \
      --data-binary "$JSON_PAYLOAD" \
      "$GOTIFY_URL" > /dev/null 2>&1; then
      # Success - silent on stdout for scripting
      exit 0
    else
      log_error "Failed to send notification to $GOTIFY_SERVER"
      exit 1
    fi
  '';

in
{
  # OPTIONS
  options.hwc.automation.gotify = {
    enable = lib.mkEnableOption "Enable gotify notification system";

    #==========================================================================
    # SERVER CONFIGURATION
    #==========================================================================
    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://hwc.ocelot-wahoo.ts.net:2586";
      description = "Gotify server URL";
    };

    defaultTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/agenix/gotify-token-alerts";
      description = "Default token file for sending notifications";
    };

    #==========================================================================
    # NOTIFICATION FORMATTING
    #==========================================================================
    defaultPriority = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 5;
      example = 7;
      description = "Default priority level (0=min, 5=normal, 10=max)";
    };

    hostTag = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically prepend hostname to message body";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Install the gotify CLI tool system-wide
    environment.systemPackages = [
      gotifySendScript
      pkgs.curl      # Required by hwc-gotify-send
      pkgs.jq        # Required for JSON payload construction
      pkgs.nettools  # Required for hostname
    ];

    # Validation
    assertions = [
      {
        assertion = cfg.serverUrl != "";
        message = "hwc.automation.gotify.serverUrl must be set";
      }
    ];
  };
}
