# domains/business/firefly/parts/automation.nix
#
# Firefly III automation timers:
#   firefly-cron   — daily hit on /api/v1/cron/<token>; without it Firefly
#                    never fires recurring transactions, bill warnings, or
#                    auto-budgets. Token comes from the firefly-cron-token
#                    agenix secret (same value baked into the container env
#                    as STATIC_CRON_TOKEN by parts/config.nix).
#   firefly-digest — daily finance summary (asset balances, bills due in the
#                    next 7 days, yesterday's transactions) posted to
#                    hwc-notify on topic=finance. Requires a Firefly personal
#                    access token at cfg.automation.digest.patFile; until that
#                    file exists the run logs a note and exits 0, so the
#                    timer ships before the token is provisioned.
{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.business.firefly;
  fireflyBase = "http://127.0.0.1:${toString cfg.reverseProxy.coreInternalPort}";
  notifyUrl = "http://127.0.0.1:11600/notify";
  cronTokenFile = config.age.secrets.firefly-cron-token.path;

  curl = "${pkgs.curl}/bin/curl";
  jq = "${pkgs.jq}/bin/jq";

  digestScript = pkgs.writeShellScript "firefly-digest" ''
    set -euo pipefail

    PAT_FILE=${lib.escapeShellArg cfg.automation.digest.patFile}
    if [ ! -r "$PAT_FILE" ]; then
      echo "firefly-digest: no personal access token at $PAT_FILE — skipping." \
           "Provision domains/secrets/parts/services/firefly-pat.age to enable."
      exit 0
    fi
    TOKEN=$(cat "$PAT_FILE")

    api() {
      ${curl} -sf --max-time 30 \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/json" \
        "${fireflyBase}/api/v1$1"
    }

    TODAY=$(date +%F)
    YESTERDAY=$(date -d yesterday +%F)
    WEEK_OUT=$(date -d '+7 days' +%F)

    BALANCES=$(api "/accounts?type=asset" | ${jq} -r \
      '.data[].attributes | select(.active) |
       "\(.name): \(.current_balance | tonumber | floor) \(.currency_code)"')

    BILLS=$(api "/bills?start=$TODAY&end=$WEEK_OUT" | ${jq} -r \
      '.data[].attributes | select(.active) |
       select((.pay_dates | length) > 0) |
       "\(.name): ~\(.amount_avg // .amount_max | tonumber | floor) due \(.pay_dates[0][:10])"')

    TXN=$(api "/transactions?start=$YESTERDAY&end=$YESTERDAY" | ${jq} -r \
      '[.data[].attributes.transactions[]] |
       "\(length) transaction(s)" +
       if length > 0 then ": " + (map(.description) | join(", ")) else "" end')

    BODY="Balances:
''${BALANCES:-none}

Bills next 7 days:
''${BILLS:-none due}

Yesterday: ''${TXN:-0 transaction(s)}"

    ${jq} -n --arg body "$BODY" \
      '{title: "Finance digest", body: $body, topic: "finance",
        source: "firefly-digest", priority: 4}' \
      | ${curl} -sf --max-time 10 -X POST -H "Content-Type: application/json" \
          -d @- "${notifyUrl}" > /dev/null
    echo "firefly-digest: sent."
  '';
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [

    (lib.mkIf cfg.automation.cron.enable {
      systemd.services.firefly-cron = {
        description = "Firefly III daily cron (recurring transactions, bills, auto-budgets)";
        after = [ "podman-firefly.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "eric";
          SupplementaryGroups = [ "secrets" ];
        };
        script = ''
          ${curl} -sf --max-time 120 \
            "${fireflyBase}/api/v1/cron/$(cat ${cronTokenFile})"
          echo "firefly-cron: ran."
        '';
      };

      systemd.timers.firefly-cron = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.automation.cron.onCalendar;
          Persistent = true;
        };
      };
    })

    (lib.mkIf cfg.automation.digest.enable {
      systemd.services.firefly-digest = {
        description = "Daily finance digest from Firefly III to hwc-notify";
        after = [ "podman-firefly.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "eric";
          SupplementaryGroups = [ "secrets" ];
          ExecStart = digestScript;
        };
      };

      systemd.timers.firefly-digest = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.automation.digest.onCalendar;
          Persistent = true;
        };
      };
    })
  ]);
}
