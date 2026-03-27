# domains/home/mail/health/index.nix
#
# Mail infrastructure health monitoring.
# Runs every 5 minutes, walks the dependency chain bottom-up:
#   GPG → pass → Bridge → mbsync → mail freshness
#
# Alert routing:
#   - Critical (mail down 30+ min): hwc-ntfy-send → phone push
#   - Warning (single failure): n8n webhook → Slack
#   - Auto-remediation: stale GPG locks cleaned automatically
#
# Boundaries:
#   - Owns: health check script, systemd timer, alert routing, state tracking
#   - Depends on: mail domain (accounts, bridge, mbsync, notmuch paths), hwc-ntfy-send
#   - Does NOT touch: mail data, configs, or services (read-only + GPG lock cleanup)
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.mail.health;
  mailCfg = config.hwc.home.mail;

  maildirRoot =
    let nmRoot = (mailCfg.notmuch or {}).maildirRoot or "";
        fallback = "${config.home.homeDirectory}/400_mail/Maildir";
    in if nmRoot != "" then nmRoot else fallback;

  stateDir = "\${XDG_STATE_HOME:-$HOME/.local/state}/mail-health";

  healthScript = pkgs.writeShellScript "mail-health-check" ''
    set -euo pipefail

    # ─── Configuration ───────────────────────────────────────────
    MAILDIR="${maildirRoot}"
    GNUPG_DIR="''${GNUPGHOME:-$HOME/.gnupg}"
    STATE_DIR="${stateDir}"
    NTFY_TOPIC="${cfg.ntfy.topic}"
    WEBHOOK_URL="${cfg.webhook.url}"
    SYNC_MAX_AGE_MIN="${toString cfg.syncMaxAgeMin}"
    FRESHNESS_HOURS="${toString cfg.freshnessHours}"
    BRIDGE_IMAP_PORT="${toString cfg.bridge.imapPort}"
    BRIDGE_SMTP_PORT="${toString cfg.bridge.smtpPort}"
    ALERT_COOLDOWN_MIN="${toString cfg.alertCooldownMin}"
    AUTO_REMEDIATE="${if cfg.autoRemediate then "true" else "false"}"

    mkdir -p "$STATE_DIR"

    # ─── Helpers ─────────────────────────────────────────────────
    FAILURES=()
    WARNINGS=()
    REMEDIATIONS=()

    fail()  { FAILURES+=("$1"); }
    warn()  { WARNINGS+=("$1"); }
    remed() { REMEDIATIONS+=("$1"); }

    now_epoch() { ${pkgs.coreutils}/bin/date +%s; }

    # Cooldown: fingerprint-based dedup so the same failure doesn't
    # spam you every 5 minutes. Keyed on md5 of the message body.
    should_alert() {
      local fp="$1" level="$2"
      local cf="$STATE_DIR/cooldown-''${level}-''${fp}"
      if [[ -f "$cf" ]]; then
        local last elapsed
        last=$(<"$cf")
        elapsed=$(( ($(now_epoch) - last) / 60 ))
        (( elapsed >= ALERT_COOLDOWN_MIN ))
      else
        return 0
      fi
    }

    record_alert() {
      local fp="$1" level="$2"
      now_epoch > "$STATE_DIR/cooldown-''${level}-''${fp}"
    }

    # ─── Alert senders ───────────────────────────────────────────

    # Critical: phone push via hwc-ntfy-send (already in PATH on server)
    send_ntfy() {
      local title="$1" body="$2" priority="''${3:-5}"
      hwc-ntfy-send --priority "$priority" --tag mail,health \
        "$NTFY_TOPIC" "$title" "$body" 2>/dev/null || true
    }

    # Warning: n8n webhook → Slack channel
    send_webhook() {
      local severity="$1" body="$2"
      [[ -z "$WEBHOOK_URL" ]] && return 0
      local payload
      payload=$(${pkgs.jq}/bin/jq -nc \
        --arg sev "$severity" \
        --arg host "$(${pkgs.hostname}/bin/hostname)" \
        --arg ts "$(${pkgs.coreutils}/bin/date -Iseconds)" \
        --arg body "$body" \
        '{severity: $sev, host: $host, timestamp: $ts, details: $body}')
      ${pkgs.curl}/bin/curl -sf -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" "$WEBHOOK_URL" >/dev/null 2>&1 || true
    }

    # Route alert to the right channel based on severity
    alert() {
      local level="$1" title="$2" body="$3"
      local fp
      fp=$(echo "$body" | ${pkgs.coreutils}/bin/md5sum | cut -d' ' -f1)

      if ! should_alert "$fp" "$level"; then
        return 0
      fi

      if [[ "$level" == "critical" ]]; then
        send_ntfy "$title" "$body" 5
        send_webhook "critical" "$body"
      else
        # Warnings go to Slack only (don't wake you up)
        send_webhook "warning" "$body"
      fi
      record_alert "$fp" "$level"
    }

    # ─── Check 1: GPG keyboxd / agent ───────────────────────────
    check_gpg() {
      # Stale lock files — THE root cause of the Mar 25 incident.
      # Bridge reads pass → pass calls gpg → gpg hangs on dead lock → everything dies.
      local -a lockfiles=()
      while IFS= read -r -d "" f; do lockfiles+=("$f"); done \
        < <(${pkgs.findutils}/bin/find "$GNUPG_DIR" -maxdepth 2 -name '*.lock' -print0 2>/dev/null)
      for lockfile in "''${lockfiles[@]}"; do
        [[ -f "$lockfile" ]] || continue
        local lock_pid=""
        lock_pid=$(${pkgs.gnugrep}/bin/grep -oP '^\d+' "$lockfile" 2>/dev/null || true)
        if [[ -z "$lock_pid" ]] || ! kill -0 "$lock_pid" 2>/dev/null; then
          if [[ "$AUTO_REMEDIATE" == "true" ]]; then
            rm -f "$lockfile"
            remed "Removed stale GPG lock: $(basename "$lockfile") (dead PID: ''${lock_pid:-unknown})"
          else
            fail "Stale GPG lock: $(basename "$lockfile") (dead PID: ''${lock_pid:-unknown})"
          fi
        fi
      done

      # Verify gpg-agent is responsive (5s timeout)
      if ! timeout 5 ${pkgs.gnupg}/bin/gpg-connect-agent /bye >/dev/null 2>&1; then
        if [[ "$AUTO_REMEDIATE" == "true" ]]; then
          ${pkgs.gnupg}/bin/gpgconf --kill gpg-agent 2>/dev/null || true
          sleep 1
          if timeout 5 ${pkgs.gnupg}/bin/gpg-connect-agent /bye >/dev/null 2>&1; then
            remed "Restarted GPG agent (was unresponsive)"
          else
            fail "GPG agent not responding (restart failed)"
          fi
        else
          fail "GPG agent not responding"
        fi
      fi

      # Check for zombie keyboxd
      local kpid
      kpid=$(${pkgs.procps}/bin/pgrep -u "$(id -u)" keyboxd 2>/dev/null | head -1 || true)
      if [[ -n "$kpid" ]]; then
        local kstate
        kstate=$(${pkgs.procps}/bin/ps -p "$kpid" -o state= 2>/dev/null || echo "?")
        if [[ "$kstate" == "Z" ]] || [[ "$kstate" == "T" ]]; then
          fail "keyboxd is zombie/stopped (PID $kpid, state $kstate)"
        fi
      fi
    }

    # ─── Check 2: pass can decrypt ──────────────────────────────
    check_pass() {
      if ! timeout 10 ${pkgs.pass}/bin/pass show email/proton/bridge >/dev/null 2>&1; then
        fail "pass cannot decrypt email/proton/bridge"
      fi
    }

    # ─── Check 3: Proton Bridge ─────────────────────────────────
    check_bridge() {
      # Service running?
      if ! ${pkgs.systemd}/bin/systemctl --user is-active protonmail-bridge.service >/dev/null 2>&1; then
        fail "protonmail-bridge.service is not running"
        return
      fi

      # IMAP port accepting connections?
      if ! timeout 5 ${pkgs.bash}/bin/bash -c \
          "echo QUIT | ${pkgs.netcat}/bin/nc -w 3 127.0.0.1 $BRIDGE_IMAP_PORT" >/dev/null 2>&1; then
        fail "Bridge IMAP port $BRIDGE_IMAP_PORT not accepting connections"
      fi

      # SMTP port (warning only — less critical than IMAP)
      if ! timeout 5 ${pkgs.bash}/bin/bash -c \
          "echo QUIT | ${pkgs.netcat}/bin/nc -w 3 127.0.0.1 $BRIDGE_SMTP_PORT" >/dev/null 2>&1; then
        warn "Bridge SMTP port $BRIDGE_SMTP_PORT not accepting connections"
      fi

      # Degraded vault detection (insecure mode = keychain broken)
      local vault_dir="$HOME/.config/protonmail/bridge-v3"
      if [[ -f "$vault_dir/insecure/vault.enc" ]] && [[ ! -f "$vault_dir/vault.enc" ]]; then
        warn "Bridge running with insecure vault — keychain may be broken"
      fi
    }

    # ─── Check 4: mbsync last successful sync ──────────────────
    check_mbsync() {
      # Timer enabled?
      if ! ${pkgs.systemd}/bin/systemctl --user is-enabled mbsync.timer >/dev/null 2>&1; then
        warn "mbsync.timer is not enabled"
      fi

      # How old is the sync state? This is the most reliable indicator
      # of "when did mail last actually sync successfully."
      local sync_state="$MAILDIR/proton/.mbsyncstate"
      if [[ -f "$sync_state" ]]; then
        local state_mtime age_min
        state_mtime=$(${pkgs.coreutils}/bin/stat -c %Y "$sync_state" 2>/dev/null || echo 0)
        age_min=$(( ($(now_epoch) - state_mtime) / 60 ))
        if (( age_min > SYNC_MAX_AGE_MIN )); then
          fail "Last mbsync state update was ''${age_min}m ago (threshold: ''${SYNC_MAX_AGE_MIN}m)"
        fi
      else
        warn "No .mbsyncstate found — mbsync may have never completed"
      fi

      # Check journal for repeated failures (sign of a systemic issue)
      local recent_failures
      recent_failures=$(${pkgs.systemd}/bin/journalctl --user -u mbsync.service \
        --since "30 min ago" --no-pager -q 2>/dev/null \
        | ${pkgs.gnugrep}/bin/grep -ci "error\|fail\|coredump\|assert" 2>/dev/null || echo 0)
      if (( recent_failures > 3 )); then
        fail "mbsync has failed ''${recent_failures} times in the last 30 minutes"
      fi
    }

    # ─── Check 5: Mail freshness ────────────────────────────────
    check_freshness() {
      local inbox_dir="$MAILDIR/proton/inbox"
      [[ -d "$inbox_dir" ]] || { warn "Inbox dir $inbox_dir missing"; return; }

      local newest
      newest=$(${pkgs.findutils}/bin/find "$inbox_dir" -type f -printf '%T@\n' 2>/dev/null \
        | ${pkgs.coreutils}/bin/sort -rn | head -1 || echo 0)

      if [[ -n "$newest" ]] && [[ "$newest" != "0" ]]; then
        local age_hours=$(( ($(now_epoch) - ''${newest%%.*}) / 3600 ))
        if (( age_hours > FRESHNESS_HOURS )); then
          warn "Newest inbox message is ''${age_hours}h old (threshold: ''${FRESHNESS_HOURS}h)"
        fi
      fi
    }

    # ─── Run all checks ─────────────────────────────────────────
    check_gpg
    check_pass
    check_bridge
    check_mbsync
    check_freshness

    # ─── Report results ─────────────────────────────────────────

    # Auto-remediations: log + send as informational warning
    if (( ''${#REMEDIATIONS[@]} > 0 )); then
      local remed_msg
      remed_msg=$(printf '• %s\n' "''${REMEDIATIONS[@]}")
      echo "AUTO-REMEDIATED:"
      echo "$remed_msg"
      alert "warning" "Mail: Auto-remediated" "$remed_msg"
    fi

    # Failures: escalate based on how long we've been failing
    if (( ''${#FAILURES[@]} > 0 )); then
      local fail_msg
      fail_msg=$(printf '• %s\n' "''${FAILURES[@]}")
      echo "FAILURES:"
      echo "$fail_msg"

      local down_file="$STATE_DIR/first-failure"
      if [[ ! -f "$down_file" ]]; then
        # First failure — record timestamp, send warning
        now_epoch > "$down_file"
        alert "warning" "Mail: Degraded" "$fail_msg"
      else
        # Ongoing failure — escalate to critical after 30 min
        local first_fail elapsed_min
        first_fail=$(<"$down_file")
        elapsed_min=$(( ($(now_epoch) - first_fail) / 60 ))
        if (( elapsed_min >= 30 )); then
          alert "critical" "Mail DOWN ''${elapsed_min}m" "$fail_msg"
        else
          alert "warning" "Mail: Degraded (''${elapsed_min}m)" "$fail_msg"
        fi
      fi
      exit 1
    fi

    # Warnings only (no failures)
    if (( ''${#WARNINGS[@]} > 0 )); then
      local warn_msg
      warn_msg=$(printf '• %s\n' "''${WARNINGS[@]}")
      echo "WARNINGS:"
      echo "$warn_msg"
      alert "warning" "Mail: Warning" "$warn_msg"
    fi

    # All clear — reset failure escalation tracking
    rm -f "$STATE_DIR/first-failure"
    echo "OK — $(${pkgs.coreutils}/bin/date -Iseconds)"
    now_epoch > "$STATE_DIR/last-healthy"
  '';

in
{
  # ════════════════════════════════════════════════════════════════
  # OPTIONS
  # ════════════════════════════════════════════════════════════════
  options.hwc.home.mail.health = {
    enable = lib.mkEnableOption "mail infrastructure health monitoring";

    ntfy = {
      topic = lib.mkOption {
        type = lib.types.str;
        default = "hwc-mail";
        description = "ntfy topic for critical alerts (uses hwc-ntfy-send which reads system ntfy config)";
      };
    };

    webhook = {
      url = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "n8n webhook URL for Slack-routed warnings";
        example = "https://hwc.ocelot-wahoo.ts.net:10000/webhook/mail-health";
      };
    };

    syncMaxAgeMin = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Alert if last successful sync was more than N minutes ago";
    };

    freshnessHours = lib.mkOption {
      type = lib.types.int;
      default = 6;
      description = "Warn if newest inbox message is older than N hours";
    };

    alertCooldownMin = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Don't re-alert for the same failure within N minutes";
    };

    autoRemediate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically fix known issues (stale GPG locks, unresponsive agent)";
    };

    bridge = {
      imapPort = lib.mkOption { type = lib.types.int; default = 1143; };
      smtpPort = lib.mkOption { type = lib.types.int; default = 1025; };
    };

    intervalMin = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "How often to run health checks (minutes)";
    };
  };

  # ════════════════════════════════════════════════════════════════
  # IMPLEMENTATION
  # ════════════════════════════════════════════════════════════════
  config = lib.mkIf cfg.enable {

    # CLI access for manual runs
    home.file.".local/bin/mail-health-check" = {
      source = healthScript;
      executable = true;
    };

    # Systemd user service (oneshot, triggered by timer)
    systemd.user.services.mail-health = {
      Unit = {
        Description = "Mail infrastructure health check";
        After = [ "default.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${healthScript}";
        Environment = [
          "PATH=${lib.makeBinPath [
            pkgs.coreutils pkgs.gnupg pkgs.pass pkgs.curl pkgs.jq
            pkgs.procps pkgs.findutils pkgs.gnugrep pkgs.netcat
            pkgs.systemd pkgs.hostname pkgs.bash
          ]}:/run/current-system/sw/bin"
          "PASSWORD_STORE_DIR=%h/.password-store"
          "GNUPGHOME=%h/.gnupg"
        ];
        Nice = 15;
      };
    };

    # Timer: every N minutes, persistent across reboots
    systemd.user.timers.mail-health = {
      Unit.Description = "Periodic mail health check";
      Timer = {
        OnBootSec = "3m";
        OnUnitActiveSec = "${toString cfg.intervalMin}m";
        AccuracySec = "30s";
        Persistent = true;
        Unit = "mail-health.service";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
