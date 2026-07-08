# domains/business/umami/parts/weekly-report.nix
#
# Weekly website-metrics email — Monday 07:00 local, best-effort.
# Pulls week-over-week stats from the Umami API (loopback :3009), top
# pages/referrers, and calculator-lead counts from postgres (hwc db),
# then mails a plain-text report via msmtp. Sender is office@ (not
# eric@) — self-sent eric→eric mail gets Proton's sent+auto-archive
# treatment and never reaches the Inbox (morning-briefing, 2026-07-06).

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.business.umami;

  reportScript = pkgs.writeShellScript "umami-weekly-report" ''
    set -uo pipefail

    UMAMI_URL="http://127.0.0.1:${toString cfg.port}"
    WID="${cfg.websiteId}"
    PW_FILE="/run/agenix/umami-admin-password"
    PSQL="/run/current-system/sw/bin/psql"

    NOW_MS=$(( $(date +%s) * 1000 ))
    WEEK_MS=$(( NOW_MS - 7 * 86400000 ))

    LOGIN=$(jq -n --rawfile pw "$PW_FILE" '{username:"admin",password:($pw|rtrimstr("\n"))}')
    TOKEN=$(curl -s -m 15 -X POST "$UMAMI_URL/api/auth/login" -H "content-type: application/json" -d "$LOGIN" | jq -r '.token // empty')
    if [ -z "$TOKEN" ]; then
      echo "umami login failed — no report sent" >&2
      exit 1
    fi
    AUTH="Authorization: Bearer $TOKEN"

    # Umami v3: stats returns flat numbers plus a `comparison` object for the
    # preceding same-length window — no second call needed.
    THIS=$(curl -s -m 15 -H "$AUTH" "$UMAMI_URL/api/websites/$WID/stats?startAt=$WEEK_MS&endAt=$NOW_MS")
    PAGES=$(curl -s -m 15 -H "$AUTH" "$UMAMI_URL/api/websites/$WID/metrics?type=path&startAt=$WEEK_MS&endAt=$NOW_MS&limit=10")
    REFS=$(curl -s -m 15 -H "$AUTH" "$UMAMI_URL/api/websites/$WID/metrics?type=referrer&startAt=$WEEK_MS&endAt=$NOW_MS&limit=10")

    # hwc.leads is the live store hwc-leads writes (hwc.calculator_leads is legacy)
    LEADS_THIS=$("$PSQL" -d hwc -tAc "SELECT count(*) FROM hwc.leads WHERE created_at > now() - interval '7 days'" 2>/dev/null | tr -d ' ')
    LEADS_PREV=$("$PSQL" -d hwc -tAc "SELECT count(*) FROM hwc.leads WHERE created_at BETWEEN now() - interval '14 days' AND now() - interval '7 days'" 2>/dev/null | tr -d ' ')
    LEADS_ROWS=$("$PSQL" -d hwc -tAc "SELECT to_char(created_at,'Mon DD')||'  '||source||'  '||coalesce(nullif(contact_name,'''),'(no name)')||'  '||status FROM hwc.leads WHERE created_at > now() - interval '7 days' ORDER BY created_at DESC" 2>/dev/null)
    [ -n "$LEADS_THIS" ] || LEADS_THIS=0
    [ -n "$LEADS_PREV" ] || LEADS_PREV=0

    BODY=$(jq -nr \
      --argjson this "$THIS" \
      --argjson pages "$PAGES" --argjson refs "$REFS" \
      --argjson lt "$LEADS_THIS" --argjson lp "$LEADS_PREV" '
      def delta(cur; old):
        if old == 0 then (if cur > 0 then " (new)" else "" end)
        else " (" + (if cur >= old then "+" else "" end) + (((cur - old) / old * 100) | round | tostring) + "%)" end;
      def row: "  " + ((.y // 0) | tostring) + "  " + (.x // "(direct)");
      ($this.comparison // {}) as $prev
      | "HEARTWOOD CRAFT — WEBSITE WEEK IN REVIEW\n"
      + "Last 7 days vs the 7 before\n"
      + "\n== TRAFFIC ==\n"
      + "visitors:  " + (($this.visitors // 0)  | tostring) + delta($this.visitors // 0;  $prev.visitors // 0) + "\n"
      + "visits:    " + (($this.visits // 0)    | tostring) + delta($this.visits // 0;    $prev.visits // 0) + "\n"
      + "pageviews: " + (($this.pageviews // 0) | tostring) + delta($this.pageviews // 0; $prev.pageviews // 0) + "\n"
      + "\n== CALCULATOR LEADS ==\n"
      + "this week: " + ($lt | tostring) + delta($lt; $lp) + "  (previous week: " + ($lp | tostring) + ")\n"
      + "\n== TOP PAGES ==\n"
      + (([$pages] | flatten | map(select(type=="object")) | map(row)) | join("\n"))
      + "\n\n== TOP REFERRERS ==\n"
      + (([$refs] | flatten | map(select(type=="object")) | map(row)) | join("\n"))
      + "\n\nFull analytics: https://stats.iheartwoodcraft.com"
      + "\nMorning dashboard: https://briefing.hwc.iheartwoodcraft.com\n"')

    if [ "$LEADS_THIS" != "0" ] && [ -n "$LEADS_ROWS" ]; then
      BODY="$BODY
== LEAD DETAIL (this week) ==
$LEADS_ROWS"
    fi

    printf 'Subject: Website Week in Review — %s\nFrom: office@iheartwoodcraft.com\nTo: %s\n\n%s\n' \
      "$(date +%Y-%m-%d)" "${cfg.weeklyReport.recipient}" "$BODY" \
      | msmtp -a proton-office "${cfg.weeklyReport.recipient}"
  '';
in
{
  options.hwc.business.umami.weeklyReport = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Weekly website-metrics email (Umami + calculator leads)";
    };
    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "Mon 07:00";
      description = "systemd OnCalendar spec (local server time)";
    };
    recipient = lib.mkOption {
      type = lib.types.str;
      default = "eric@iheartwoodcraft.com";
      description = "Report recipient";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.weeklyReport.enable) {
    systemd.services.umami-weekly-report = {
      description = "Weekly website metrics email (umami + calculator leads)";
      after = [ "network-online.target" "podman-umami.service" ];
      wants = [ "network-online.target" ];
      environment.HOME = config.hwc.paths.user.home;
      # pass+gnupg: msmtp passwordeval (proton bridge), same as morning-briefing
      path = [ pkgs.bash pkgs.coreutils pkgs.curl pkgs.jq pkgs.msmtp pkgs.pass pkgs.gnupg ];
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        ExecStart = "${reportScript}";
        TimeoutSec = 120;
      };
    };

    systemd.timers.umami-weekly-report = {
      description = "Weekly website metrics email timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.weeklyReport.onCalendar;
        Persistent = true;
        RandomizedDelaySec = 300;
      };
    };
  };
}
