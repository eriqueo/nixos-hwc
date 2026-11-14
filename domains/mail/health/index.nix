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
#     health-cases, hwc-notify, optionally the tracker hub through the
#     hwc-tracker client (agent-harness)
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
  staleLock = lib.getExe config.hwc.home.apps.gpg.staleLock.package;
  trackerUrl = lib.attrByPath [ "hwc" "home" "apps" "agent-harness" "tracker" "url" ] null config;
  # Referenced only with a project set, so a host without cards never builds the client.
  trackerOn = cfg.tracker.project != null && cfg.tracker.client != null && trackerUrl != null;

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
    TRACKER_PROJECT=${lib.escapeShellArg (if trackerOn then cfg.tracker.project else "")}
    TRACKER_CLIENT=${lib.escapeShellArg (if trackerOn then "${cfg.tracker.client}/bin/hwc-tracker" else "")}
    TRACKER_URL=${lib.escapeShellArg (if trackerOn then trackerUrl else "")}
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
      # Stale lock files — THE root cause of the Mar 25 incident. The decision
      # belongs to hwc-gpg-stale-lock (domains/home/apps/gpg); this only reports.
      # The old inline test read the PID with `^\d+`, but dotlock writes it
      # right-aligned, so every lock (live ones too) looked stale and was removed.
      local mode=--check verb path reason pid
      [[ "$AUTO_REMEDIATE" == "true" ]] && mode=--apply
      while read -r verb path reason pid; do
        reason="''${reason#reason=}"; pid="''${pid#pid=}"
        case "$verb" in
          removed) remed "Removed stale GPG lock: $(basename "$path") ($reason, PID: $pid)" ;;
          stale)   infra gpg-stale-lock "Stale GPG lock: $(basename "$path") ($reason, PID: $pid)" ;;
          failed)  infra gpg-stale-lock "Could not remove stale GPG lock: $(basename "$path") ($reason, PID: $pid)" ;;
        esac
      done < <(GNUPGHOME="$GNUPG_DIR" ${staleLock} "$mode" 2>&1 || true)
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
    # The tracker hub owns its records. Every run sends the hub the complete set
    # of cards that should be open now (ids MH-*), the empty set included, as one
    # sync-health-cards command; the hub opens, closes and reopens cards to match.
    # A run the hub missed is repaired by the next one. Nothing here writes a
    # tracker file or decides that a card is closed.
    card_id() { printf 'MH-%s' "$(printf '%s' "$1" | ${pkgs.coreutils}/bin/sha256sum | cut -c1-8)"; }
    # Prints one line. Returns 0 when the command was sent, and also when the hub
    # was unreachable or its outcome is unknown: the next run sends the full set
    # again. Returns 1 when the hub or the client refused the command, which no
    # later run repairs.
    sync_health_cards() {
      local open='[]' item id digest sent="" last="" out status=0
      while IFS= read -r item; do
        [[ -n "$item" ]] || continue
        id=$(card_id "$(jq -r '.caseId' <<<"$item")") || return 1
        open=$(jq -c --arg id "$id" --arg host "$HOST" --argjson item "$item" '
          . + [$item | (.openSeconds / 3600 | floor | tostring) as $hours | {
            id: $id, kind: "decision",
            title: ("Mail health: " + .lane + " " + .code + " open for " + $hours + "h"),
            ask: (.message // .caseId),
            context: ("Case " + .caseId + " on " + $host + " has been open since " + ((now - .openSeconds) | todate)
              + " (outcome " + .outcome + "). The alert fired once when it opened; this card exists because nobody acted in "
              + $hours + " hours."),
            plan: "Run the named command on the host, or say the case can stay open. The card closes itself when the case clears.",
            risk: "An open mail health case left unactioned keeps masking a real outage.",
            recommend: "approve"}]' <<<"$open") || { echo "mail-health: could not build the card for $id" >&2; return 1; }
      done < <(jq -c '.stale[]' <<<"$REPORT")
      # The command id names one desired set from the moment it was first tried.
      # An unchanged set keeps its id, so a run repeated after an unreachable hub
      # or an unknown outcome is the same command and cannot apply twice. A changed
      # set takes a new id: the hub conflicts on one id carrying two payloads. The
      # moment is part of the id because the hub answers a remembered id without
      # reconciling again; a set that comes back (empty, one card, empty) would
      # otherwise replay its first answer and leave the card open.
      digest=$(printf '%s' "$open" | ${pkgs.coreutils}/bin/sha256sum | cut -c1-32) || return 1
      if [[ -f "$STATE_DIR/tracker-command" ]]; then read -r sent last < "$STATE_DIR/tracker-command" || true; fi
      if [[ "$last" != "$digest" || ! "$sent" =~ ^[0-9]+$ ]]; then
        sent=$(${pkgs.coreutils}/bin/date +%s%N)
        if ! { printf '%s %s\n' "$sent" "$digest" > "$STATE_DIR/tracker-command.tmp" \
               && mv "$STATE_DIR/tracker-command.tmp" "$STATE_DIR/tracker-command"; }; then
          echo "mail-health: could not record the card command id; nothing was sent to the tracker hub" >&2
          return 1
        fi
      fi
      out=$("$TRACKER_CLIENT" sync-health-cards "$TRACKER_PROJECT" --url "$TRACKER_URL" --text \
              --command-id "mh-$sent-$digest" --input - <<<"$open" 2>&1) || status=$?
      out=$(printf '%s' "$out" | tr '\n' ' ')
      case "$status" in
        0) echo "cards: $(jq -r 'length' <<<"$open") open on $TRACKER_PROJECT (''${out%% *})" ;;
        3) echo "mail-health: tracker hub $TRACKER_URL unreachable; cards not synced this run, the next run sends the full set" >&2 ;;
        6) echo "mail-health: tracker hub $TRACKER_URL gave no clear answer; cards may or may not be synced, the next run sends the full set" >&2 ;;
        *) echo "mail-health: card sync refused (hwc-tracker exit $status): $out" >&2; return 1 ;;
      esac
    }
    CARDS_BROKEN=""
    if [[ -n "$TRACKER_PROJECT" ]]; then
      sync_health_cards || CARDS_BROKEN=1
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
    # Everything above ran and summary.json is current. A refused card sync is a
    # broken part of the checker, so it fails the unit; an unreachable hub does not.
    if [[ -n "$CARDS_BROKEN" ]]; then exit 1; fi
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
          Each run sends the hub the full set of cards that should be open.
          Enable on ONE host only: a second sender's set would close the first's cards.
        '';
      };
      client = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = lib.attrByPath [ "hwc" "home" "apps" "agent-harness" "tracker" "package" ] null config;
        defaultText = lib.literalExpression "config.hwc.home.apps.agent-harness.tracker.package (null without the app)";
        description = ''
          The `hwc-tracker` client that carries the cards to the hub
          (`sync-health-cards`). The hub address is the agent-harness
          `tracker.url`. Used only when tracker.project is set.
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
      assertion = cfg.tracker.project == null || trackerOn;
      message = "hwc.mail.health.tracker.project needs the hwc-tracker client and hub URL (hwc.home.apps.agent-harness.tracker.{package,url}) on this host";
    } {
      # check_gpg calls hwc-gpg-stale-lock, which the gpg app owns.
      assertion = config.hwc.home.apps.gpg.enable;
      message = "hwc.mail.health needs hwc.home.apps.gpg.enable (stale-lock helper)";
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
