# domains/mail/health/index.nix
#
# Mail infrastructure health monitoring.
# Runs every 5 minutes. The local checks (GPG → pass → Bridge → inbox freshness)
# become issues in the same shape System One derives from the sync status, and
# System One's `health-cases` holds the ONE case store for all of them:
# transitions (open / escalate / close) are what alert, never repeats.
#
# Severity is by consequence (Eric, 2026-10-12):
#   critical  mail is not arriving: fetch/index stale, or an infrastructure
#             failure open for escalateMin minutes
#   warning   everything a person should look at while delivery still works:
#             a command backlog, label conflicts, a fresh failed attempt
# A case open longer than staleHours becomes a card on the tracker project,
# and the card closes itself when the case clears.
#
# The unit's exit code means "did the checker run", not "is mail healthy":
# a failed unit is a broken checker. Health lives in summary.json, the case
# store, the alerts and the card.
#
# Boundaries:
#   - Owns: local checks, systemd timer, alert and card routing, summary.json
#   - Depends on: mail domain (bridge, mbsync status path), System One
#     health-cases, hwc-notify, optionally the tracker root (agent-harness)
#   - Does NOT touch: mail data, configs, or services (read-only + GPG lock cleanup)
{ config, lib, pkgs, inputs, osConfig ? {}, ... }:
let
  cfg = config.hwc.mail.health;
  mailCfg = config.hwc.mail;

  maildirRoot =
    let nmRoot = (mailCfg.notmuch or {}).maildirRoot or "";
        fallback = "${config.home.homeDirectory}/400_mail/Maildir";
    in if nmRoot != "" then nmRoot else fallback;

  stateDir = "\${XDG_STATE_HOME:-$HOME/.local/state}/mail-health";
  trackerRoot = lib.attrByPath [ "hwc" "home" "apps" "agent-harness" "tracker" "root" ] null config;
  trackerFile = if cfg.tracker.project != null && trackerRoot != null
                then "${trackerRoot}/${cfg.tracker.project}/tracker.json" else "";

  healthScript = pkgs.writeShellScript "mail-health-check" ''
    set -euo pipefail

    # ─── Configuration ───────────────────────────────────────────
    MAILDIR="${maildirRoot}"
    GNUPG_DIR="''${GNUPGHOME:-$HOME/.gnupg}"
    STATE_DIR="${stateDir}"
    WEBHOOK_URL="${cfg.webhook.url}"
    NOTIFY_URL="${if cfg.notify.url != null then cfg.notify.url else ""}"
    SYNC_MAX_AGE_MIN="${toString cfg.syncMaxAgeMin}"
    FRESHNESS_HOURS="${toString cfg.freshnessHours}"
    ESCALATE_SECONDS="${toString (cfg.escalateMin * 60)}"
    STALE_SECONDS="${toString (cfg.staleHours * 3600)}"
    BRIDGE_IMAP_PORT="${toString cfg.bridge.imapPort}"
    BRIDGE_SMTP_PORT="${toString cfg.bridge.smtpPort}"
    BRIDGE_LOCAL="${if (config.hwc.mail.bridge.enable or false) then "true" else "false"}"
    AUTO_REMEDIATE="${if cfg.autoRemediate then "true" else "false"}"
    SYNC_STATUS=${lib.escapeShellArg (config.hwc.paths.user.mailSyncStatus or "${config.home.homeDirectory}/.local/state/mail-sync/status.json")}
    TRACKER_FILE=${lib.escapeShellArg trackerFile}
    HOST="$(${pkgs.hostname}/bin/hostname)"
    jq() { ${pkgs.jq}/bin/jq "$@"; }

    mkdir -p "$STATE_DIR"
    # The pre-2026-10-12 script kept its own cooldown and escalation files here.
    # The case store owns that now; remove what is left so nothing reads it.
    rm -f "$STATE_DIR"/cooldown-* "$STATE_DIR/first-failure"

    # ─── Issues (one shape, shared with System One) ─────────────
    ISSUES_FILE="$STATE_DIR/infra-issues.json"
    echo '[]' > "$ISSUES_FILE"
    REMEDIATIONS=()
    remed() { REMEDIATIONS+=("$1"); }
    # issue <lane> <code> <outcome> <message> [escalateAfterSeconds]
    issue() {
      local lane="$1" code="$2" outcome="$3" message="$4" escalate="''${5:-}"
      jq -c --arg lane "$lane" --arg code "$code" --arg outcome "$outcome" --arg message "$message" \
        --arg escalate "$escalate" --arg host "$HOST" \
        '. + [{caseId: (["mail-health", $host, $lane, $code] | join(":")), lane: $lane, code: $code, state: "open",
               outcome: $outcome, message: $message}
              + (if $escalate == "" then {} else {escalateAfter: ($escalate | tonumber), escalatedOutcome: "critical"} end)]' \
        "$ISSUES_FILE" > "$ISSUES_FILE.tmp" && mv "$ISSUES_FILE.tmp" "$ISSUES_FILE"
    }
    # Infrastructure failures: a warning first, critical once open ESCALATE_SECONDS.
    infra() { issue infrastructure "$1" warning "$2" "$ESCALATE_SECONDS"; }

    now_epoch() { ${pkgs.coreutils}/bin/date +%s; }

    # ─── Alert senders ───────────────────────────────────────────
    send_webhook() {   # n8n → Slack
      local severity="$1" body="$2"
      [[ -z "$WEBHOOK_URL" ]] && return 0
      jq -nc --arg sev "$severity" --arg host "$HOST" \
        --arg ts "$(${pkgs.coreutils}/bin/date -Iseconds)" --arg body "$body" \
        '{severity: $sev, host: $host, timestamp: $ts, details: $body}' \
        | ${pkgs.curl}/bin/curl -sf -X POST -H "Content-Type: application/json" -d @- "$WEBHOOK_URL" >/dev/null 2>&1 || true
    }
    send_notify() {    # hwc-notify, priority 1: Discord fanout + email. Fail-soft.
      local title="$1" body="$2"
      [[ -z "$NOTIFY_URL" ]] && return 0
      jq -nc --arg t "$title" --arg b "$body ($HOST)" \
        '{topic:"monitoring", source:"mail-health", title:$t, body:$b, priority:1, tags:["mail","critical"]}' \
        | ${pkgs.curl}/bin/curl -sf --max-time 8 -X POST -H "Content-Type: application/json" -d @- "$NOTIFY_URL/notify" >/dev/null 2>&1 || true
    }

    # ─── Check 1: GPG keyboxd / agent ───────────────────────────
    check_gpg() {
      # Stale lock files — THE root cause of the Mar 25 incident.
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
            infra gpg-stale-lock "Stale GPG lock: $(basename "$lockfile") (dead PID: ''${lock_pid:-unknown})"
          fi
        fi
      done
      if ! timeout 5 ${pkgs.gnupg}/bin/gpg-connect-agent /bye >/dev/null 2>&1; then
        if [[ "$AUTO_REMEDIATE" == "true" ]]; then
          ${pkgs.gnupg}/bin/gpgconf --kill gpg-agent 2>/dev/null || true
          sleep 1
          if timeout 5 ${pkgs.gnupg}/bin/gpg-connect-agent /bye >/dev/null 2>&1; then
            remed "Restarted GPG agent (was unresponsive)"
          else
            infra gpg-agent-down "GPG agent not responding (restart failed)"
          fi
        else
          infra gpg-agent-down "GPG agent not responding"
        fi
      fi
      local kpid
      kpid=$(${pkgs.procps}/bin/pgrep -u "$(id -u)" keyboxd 2>/dev/null | head -1 || true)
      if [[ -n "$kpid" ]]; then
        local kstate
        kstate=$(${pkgs.procps}/bin/ps -p "$kpid" -o state= 2>/dev/null || echo "?")
        if [[ "$kstate" == "Z" ]] || [[ "$kstate" == "T" ]]; then
          infra keyboxd-stuck "keyboxd is zombie/stopped (PID $kpid, state $kstate)"
        fi
      fi
    }

    # ─── Check 2: pass can decrypt ──────────────────────────────
    check_pass() {
      if ! timeout 10 ${pkgs.pass}/bin/pass show email/proton/bridge >/dev/null 2>&1; then
        infra pass-decrypt-failed "pass cannot decrypt email/proton/bridge"
      fi
    }

    # ─── Check 3: Proton Bridge ─────────────────────────────────
    check_bridge() {
      # Only where the bridge runs locally; a relay host reaches another host's
      # bridge and the greeting checks below cover that path.
      if [[ "$BRIDGE_LOCAL" == "true" ]] \
         && ! ${pkgs.systemd}/bin/systemctl --user is-active protonmail-bridge.service >/dev/null 2>&1; then
        if [[ "$AUTO_REMEDIATE" == "true" ]]; then
          ${pkgs.systemd}/bin/systemctl --user restart protonmail-bridge.service 2>/dev/null || true
          sleep 5
          if ${pkgs.systemd}/bin/systemctl --user is-active protonmail-bridge.service >/dev/null 2>&1; then
            remed "Restarted protonmail-bridge.service (was not running)"
          else
            infra bridge-down "protonmail-bridge.service is not running (auto-restart failed)"
            return
          fi
        else
          infra bridge-down "protonmail-bridge.service is not running"
          return
        fi
      fi
      # Greetings, not bare connects: a relay port accepts TCP while the bridge
      # behind it is down; only the protocol banner proves the bridge answered.
      local imap_greet smtp_greet
      imap_greet=$(timeout 5 ${pkgs.bash}/bin/bash -c \
          "echo QUIT | ${pkgs.netcat}/bin/nc -w 3 127.0.0.1 $BRIDGE_IMAP_PORT" 2>/dev/null || true)
      if [[ "$imap_greet" != "* OK"* ]]; then
        infra bridge-imap-silent "Bridge IMAP port $BRIDGE_IMAP_PORT did not greet"
      fi
      smtp_greet=$(timeout 5 ${pkgs.bash}/bin/bash -c \
          "echo QUIT | ${pkgs.netcat}/bin/nc -w 3 127.0.0.1 $BRIDGE_SMTP_PORT" 2>/dev/null || true)
      if [[ "$smtp_greet" != "220"* ]]; then
        issue infrastructure bridge-smtp-silent warning "Bridge SMTP port $BRIDGE_SMTP_PORT did not greet"
      fi
      local vault_dir="$HOME/.config/protonmail/bridge-v3"
      if [[ "$BRIDGE_LOCAL" == "true" ]] \
         && [[ -f "$vault_dir/insecure/vault.enc" ]] && [[ ! -f "$vault_dir/vault.enc" ]]; then
        issue infrastructure bridge-insecure-vault warning "Bridge running with insecure vault — keychain may be broken"
      fi
    }

    # ─── Check 4: Mail freshness ────────────────────────────────
    check_freshness() {
      local inbox_dir="$MAILDIR/proton/inbox"
      [[ -d "$inbox_dir" ]] || { issue freshness inbox-dir-missing warning "Inbox dir $inbox_dir missing"; return; }
      local newest
      newest=$(${pkgs.findutils}/bin/find "$inbox_dir" -type f -printf '%T@\n' 2>/dev/null \
        | ${pkgs.coreutils}/bin/sort -rn 2>/dev/null | head -1 || echo 0)
      if [[ -n "$newest" ]] && [[ "$newest" != "0" ]]; then
        local age_hours=$(( ($(now_epoch) - ''${newest%%.*}) / 3600 ))
        if (( age_hours > FRESHNESS_HOURS )); then
          issue freshness inbox-stale warning "Newest inbox message is ''${age_hours}h old (threshold: ''${FRESHNESS_HOURS}h)"
        fi
      fi
    }

    check_gpg
    check_pass
    check_bridge
    check_freshness

    # ─── Assessment: one case store, transitions only ───────────
    if ! REPORT=$(${pkgs.python3}/bin/python3 ${inputs.system-one}/scripts/mail_classifier.py health-cases \
          --status "$SYNC_STATUS" --db "$STATE_DIR/cases.sqlite" \
          --availability-seconds "$(( SYNC_MAX_AGE_MIN * 60 ))" \
          --extra-issues "$ISSUES_FILE" --stale-seconds "$STALE_SECONDS"); then
      echo "mail-health: case assessment failed; the checker is broken, not the mail" >&2
      exit 1
    fi

    if (( ''${#REMEDIATIONS[@]} > 0 )); then   # events, not states: report once, no case
      remed_msg=$(printf '• %s\n' "''${REMEDIATIONS[@]}")
      echo "AUTO-REMEDIATED:"; echo "$remed_msg"
      send_webhook warning "$remed_msg"
    fi

    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      state=$(jq -r '.state' <<<"$item"); outcome=$(jq -r '.outcome' <<<"$item")
      message=$(jq -r '.message // .caseId' <<<"$item"); lane=$(jq -r '.lane // "mail"' <<<"$item")
      if [[ "$state" == closed ]]; then
        send_webhook info "cleared: $message"
      elif [[ "$outcome" == critical ]]; then
        send_webhook critical "$message"
        send_notify "Mail $lane needs action" "$message"
      else
        send_webhook warning "$message"
      fi
    done < <(jq -c '.transitions[]' <<<"$REPORT")

    # ─── Cards: a case open past STALE_SECONDS is a decision for Eric ──
    # tracker.json is the agents' file; this is a bounded second writer for ids
    # MH-*, written whole and atomically. The card closes when the case clears.
    card_id() { printf 'MH-%s' "$(printf '%s' "$1" | ${pkgs.coreutils}/bin/sha256sum | cut -c1-8)"; }
    if [[ -n "$TRACKER_FILE" && -f "$TRACKER_FILE" ]]; then
      now_iso=$(${pkgs.coreutils}/bin/date -Iseconds)
      while IFS= read -r item; do
        [[ -n "$item" ]] || continue
        id=$(card_id "$(jq -r '.caseId' <<<"$item")")
        if jq -e --arg id "$id" 'any(.cards[]?; .id==$id and (.done|not))' "$TRACKER_FILE" >/dev/null; then continue; fi
        hours=$(jq -r '(.openSeconds / 3600 | floor)' <<<"$item")
        jq --arg id "$id" --arg now "$now_iso" \
           --arg title "Mail health: $(jq -r '.lane + " " + .code' <<<"$item") open for ''${hours}h" \
           --arg ask "$(jq -r '.message' <<<"$item")" \
           --arg context "Case $(jq -r '.caseId' <<<"$item") on $HOST has been open since $(jq -r '(now - .openSeconds) | todate' <<<"$item") (outcome $(jq -r '.outcome' <<<"$item")). The alert fired once when it opened; this card exists because nobody acted in ''${hours} hours." \
           '.cards = ((.cards // []) | map(select(.id != $id))) + [{id: $id, kind: "decision", title: $title, ask: $ask, context: $context,
              plan: "Run the named command on the host, or say the case can stay open. The card closes itself when the case clears.",
              risk: "An open mail health case left unactioned keeps masking a real outage.", recommend: "approve", done: false}]
            | .updated = $now' "$TRACKER_FILE" > "$TRACKER_FILE.tmp" && mv "$TRACKER_FILE.tmp" "$TRACKER_FILE"
        echo "card $id opened on $(basename "$(dirname "$TRACKER_FILE")")"
      done < <(jq -c '.stale[]' <<<"$REPORT")
      while IFS= read -r item; do
        [[ -n "$item" ]] || continue
        id=$(card_id "$(jq -r '.caseId' <<<"$item")")
        if jq -e --arg id "$id" 'any(.cards[]?; .id==$id and (.done|not))' "$TRACKER_FILE" >/dev/null; then
          jq --arg id "$id" --arg now "$now_iso" \
             '.cards |= map(if .id==$id then .done=true else . end) | .updated=$now' \
             "$TRACKER_FILE" > "$TRACKER_FILE.tmp" && mv "$TRACKER_FILE.tmp" "$TRACKER_FILE"
          echo "card $id closed"
        fi
      done < <(jq -c '.transitions[] | select(.state=="closed")' <<<"$REPORT")
    fi

    # ─── Publish ────────────────────────────────────────────────
    jq -c --arg at "$(${pkgs.coreutils}/bin/date -Iseconds)" --arg host "$HOST" \
       '{schemaVersion: 1, at: $at, host: $host, checker: "ok", issues: .issues, stale: .stale}' <<<"$REPORT" \
       > "$STATE_DIR/summary.json.tmp" && mv "$STATE_DIR/summary.json.tmp" "$STATE_DIR/summary.json"
    jq -r '.issues[] | .outcome + ": " + .message' <<<"$REPORT"
    if ! jq -e '.issues | any(.outcome == "critical")' <<<"$REPORT" >/dev/null; then
      now_epoch > "$STATE_DIR/last-healthy"
      echo "OK — $(${pkgs.coreutils}/bin/date -Iseconds)"
    fi
  '';

in
{
  # ════════════════════════════════════════════════════════════════
  # OPTIONS
  # ════════════════════════════════════════════════════════════════
  options.hwc.mail.health = {
    enable = lib.mkEnableOption "mail infrastructure health monitoring";

    webhook = {
      url = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "n8n webhook URL for Slack-routed transitions";
        example = "https://hwc-server.ocelot-wahoo.ts.net:10000/webhook/mail-health";
      };
    };

    notify = {
      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = lib.attrByPath [ "hwc" "notifications" "notify" "url" ] null osConfig;
        defaultText = lib.literalExpression "osConfig.hwc.notifications.notify.url (null without it)";
        description = ''
          hwc-notify base URL. Critical transitions POST here with priority 1
          (Discord fanout + email). Defaults to the system's single producer,
          hwc.notifications.notify.url. null = disabled.
        '';
      };
    };

    tracker = {
      project = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "proton-mail";
        description = ''
          Tracker project that receives a decision card (id MH-*) when a case
          stays open past staleHours. The card closes when the case clears.
          Needs hwc.home.apps.agent-harness.tracker.root on the same host.
          Enable on ONE host only: the tracker root is synced between hosts.
        '';
      };
    };

    syncMaxAgeMin = lib.mkOption {
      type = lib.types.int;
      default = 45;
      description = "Critical when fetch/index last succeeded more than N minutes ago";
    };

    freshnessHours = lib.mkOption {
      type = lib.types.int;
      default = 6;
      description = "Warn if newest inbox message is older than N hours";
    };

    escalateMin = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "An infrastructure failure (GPG, pass, Bridge) is a warning until it has been open N minutes, then critical";
    };

    staleHours = lib.mkOption {
      type = lib.types.int;
      default = 24;
      description = "A case open N hours becomes a tracker card (when tracker.project is set)";
    };

    autoRemediate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically fix known issues (stale GPG locks, unresponsive agent, stopped bridge)";
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
    assertions = [{
      assertion = cfg.tracker.project == null || trackerRoot != null;
      message = "hwc.mail.health.tracker.project needs hwc.home.apps.agent-harness.tracker.root on this host";
    }];

    # CLI access for manual runs
    home.file.".local/bin/mail-health-check" = {
      source = healthScript;
      executable = true;
    };

    # Systemd user service (oneshot, triggered by timer). Exit 1 = the checker
    # itself failed; mail health is in summary.json, the case store and alerts.
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
