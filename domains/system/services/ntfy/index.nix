# domains/system/services/ntfy/index.nix
#
# NTFY - Centralized notification system for cross-machine and cross-service alerts.
# Provides a reusable CLI tool (hwc-ntfy-send) that can be called from backup scripts,
# systemd services, or any other component that needs to send notifications.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.ntfy;

  # Build the hwc-ntfy-send CLI tool
  ntfySendScript = pkgs.writeScriptBin "hwc-ntfy-send" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # Configuration from NixOS module
    NTFY_SERVER="${cfg.serverUrl}"
    DEFAULT_TOPIC="${if cfg.defaultTopic != null then cfg.defaultTopic else ""}"
    DEFAULT_TAGS="${lib.concatStringsSep "," cfg.defaultTags}"
    DEFAULT_PRIORITY="${if cfg.defaultPriority != null then toString cfg.defaultPriority else ""}"
    HOST_TAG_ENABLED="${if cfg.hostTag then "true" else "false"}"
    AUTH_ENABLED="${if cfg.auth.enable then "true" else "false"}"
    AUTH_METHOD="${cfg.auth.method}"
    ${lib.optionalString (cfg.auth.tokenFile != null) ''
      AUTH_TOKEN_FILE="${cfg.auth.tokenFile}"
    ''}
    ${lib.optionalString (cfg.auth.userFile != null) ''
      AUTH_USER_FILE="${cfg.auth.userFile}"
    ''}
    ${lib.optionalString (cfg.auth.passFile != null) ''
      AUTH_PASS_FILE="${cfg.auth.passFile}"
    ''}

    # Get hostname for tagging
    HOSTNAME="$(${pkgs.nettools}/bin/hostname)"

    # Usage information
    usage() {
      cat <<EOF
Usage: hwc-ntfy-send [OPTIONS] <topic> <title> <message>

Send notifications via ntfy server.

Arguments:
  <topic>      Topic to send to (use '-' for default topic)
  <title>      Notification title (use '-' to omit title)
  <message>    Notification message body

Options:
  --tag TAG[,TAG...]    Additional tags (comma-separated)
  --priority LEVEL      Priority (1=min, 3=default, 5=max)
  --help, -h            Show this help message

Examples:
  hwc-ntfy-send backup-alerts "Backup Success" "All files backed up"
  hwc-ntfy-send - "Test" "Using default topic"
  hwc-ntfy-send alerts - "Message without title"
  hwc-ntfy-send --tag urgent --priority 5 alerts "Critical" "System down"

Configuration:
  Server:         $NTFY_SERVER
  Default Topic:  ''${DEFAULT_TOPIC:-<none>}
  Default Tags:   ''${DEFAULT_TAGS:-<none>}
  Host Tagging:   $HOST_TAG_ENABLED
  Auth Enabled:   $AUTH_ENABLED
EOF
      exit 0
    }

    # Error logging
    log_error() {
      echo "ERROR: $1" >&2
    }

    # Parse command-line arguments
    EXTRA_TAGS=""
    EXTRA_PRIORITY=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --help|-h)
          usage
          ;;
        --tag)
          shift
          EXTRA_TAGS="$1"
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
    if [[ $# -lt 3 ]]; then
      log_error "Missing required arguments"
      echo "" >&2
      usage
    fi

    TOPIC="$1"
    TITLE="$2"
    MESSAGE="$3"

    # Use default topic if '-' is specified
    if [[ "$TOPIC" == "-" ]]; then
      if [[ -z "$DEFAULT_TOPIC" ]]; then
        log_error "No topic specified and no default topic configured"
        exit 1
      fi
      TOPIC="$DEFAULT_TOPIC"
    fi

    # Build the ntfy URL
    NTFY_URL="$NTFY_SERVER/$TOPIC"

    # Build tags: combine default tags, host tag, and extra tags
    TAGS_ARRAY=()

    # Add default tags
    if [[ -n "$DEFAULT_TAGS" ]]; then
      IFS=',' read -ra TAG_LIST <<< "$DEFAULT_TAGS"
      for tag in "''${TAG_LIST[@]}"; do
        [[ -n "$tag" ]] && TAGS_ARRAY+=("$tag")
      done
    fi

    # Add hostname tag if enabled
    if [[ "$HOST_TAG_ENABLED" == "true" ]]; then
      TAGS_ARRAY+=("host-$HOSTNAME")
    fi

    # Add extra tags from command line
    if [[ -n "$EXTRA_TAGS" ]]; then
      IFS=',' read -ra TAG_LIST <<< "$EXTRA_TAGS"
      for tag in "''${TAG_LIST[@]}"; do
        [[ -n "$tag" ]] && TAGS_ARRAY+=("$tag")
      done
    fi

    # Combine all tags
    FINAL_TAGS=$(IFS=','; echo "''${TAGS_ARRAY[*]}")

    # Determine priority (command-line overrides default)
    FINAL_PRIORITY="$EXTRA_PRIORITY"
    if [[ -z "$FINAL_PRIORITY" && -n "$DEFAULT_PRIORITY" ]]; then
      FINAL_PRIORITY="$DEFAULT_PRIORITY"
    fi

    # Build curl command arguments
    CURL_ARGS=()

    # Add title header (unless it's '-')
    if [[ "$TITLE" != "-" ]]; then
      CURL_ARGS+=("-H" "Title: $TITLE")
    fi

    # Add tags header if we have any
    if [[ -n "$FINAL_TAGS" ]]; then
      CURL_ARGS+=("-H" "Tags: $FINAL_TAGS")
    fi

    # Add priority header if specified
    if [[ -n "$FINAL_PRIORITY" ]]; then
      CURL_ARGS+=("-H" "Priority: $FINAL_PRIORITY")
    fi

    # Add authentication if enabled
    if [[ "$AUTH_ENABLED" == "true" ]]; then
      if [[ "$AUTH_METHOD" == "token" ]]; then
        if [[ -z "''${AUTH_TOKEN_FILE:-}" ]]; then
          log_error "Token authentication enabled but tokenFile not configured"
          exit 1
        fi
        if [[ ! -f "$AUTH_TOKEN_FILE" ]]; then
          log_error "Token file does not exist: $AUTH_TOKEN_FILE"
          exit 1
        fi
        TOKEN=$(${pkgs.coreutils}/bin/cat "$AUTH_TOKEN_FILE")
        CURL_ARGS+=("-H" "Authorization: Bearer $TOKEN")
      elif [[ "$AUTH_METHOD" == "basic" ]]; then
        if [[ -z "''${AUTH_USER_FILE:-}" || -z "''${AUTH_PASS_FILE:-}" ]]; then
          log_error "Basic authentication enabled but userFile or passFile not configured"
          exit 1
        fi
        if [[ ! -f "$AUTH_USER_FILE" || ! -f "$AUTH_PASS_FILE" ]]; then
          log_error "Auth files do not exist"
          exit 1
        fi
        USER=$(${pkgs.coreutils}/bin/cat "$AUTH_USER_FILE")
        PASS=$(${pkgs.coreutils}/bin/cat "$AUTH_PASS_FILE")
        CURL_ARGS+=("-u" "$USER:$PASS")
      fi
    fi

    # Send the notification
    if ${pkgs.curl}/bin/curl -fsSL \
      "''${CURL_ARGS[@]}" \
      --data-binary "$MESSAGE" \
      "$NTFY_URL" > /dev/null 2>&1; then
      # Success - silent on stdout for scripting
      exit 0
    else
      log_error "Failed to send notification to $NTFY_URL"
      exit 1
    fi
  '';

in
{
  #==========================================================================
  # MODULE AGGREGATION
  #==========================================================================
  imports = [
    ./options.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Install the ntfy CLI tool system-wide
    environment.systemPackages = [
      ntfySendScript
      pkgs.curl      # Required by hwc-ntfy-send
      pkgs.nettools  # Required for hostname
    ];

    # Validation: ensure required options are set
    assertions = [
      {
        assertion = cfg.defaultTopic != null || true;  # defaultTopic is optional
        message = "ntfy can work without a default topic, but users must specify topic explicitly";
      }
      {
        assertion = !cfg.auth.enable || (cfg.auth.method == "token" && cfg.auth.tokenFile != null) || (cfg.auth.method == "basic" && cfg.auth.userFile != null && cfg.auth.passFile != null);
        message = "ntfy authentication enabled but required file paths not configured for method '${cfg.auth.method}'";
      }
    ];

    # Warnings for common misconfigurations
    warnings = lib.optional (cfg.auth.enable && cfg.auth.method == "token" && cfg.auth.tokenFile == null) "ntfy token auth enabled but tokenFile not set"
      ++ lib.optional (cfg.auth.enable && cfg.auth.method == "basic" && (cfg.auth.userFile == null || cfg.auth.passFile == null)) "ntfy basic auth enabled but userFile or passFile not set";
  };
}
