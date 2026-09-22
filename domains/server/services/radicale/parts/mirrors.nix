# domains/server/services/radicale/parts/mirrors.nix
#
# Read-only mirrors of outside calendars INTO Radicale.
#
# Each mirror is one secret iCal address (agenix secret, one URL, no newline
# needed) copied into one Radicale collection under the `eric` principal by
# vdirsyncer's `http` storage. Everything that already reads Radicale then sees
# the outside calendar for free: the iPhone's CalDAV account (it discovers
# every collection under /eric/), khal/ikhal on both machines (their VEVENT pair
# pins the ids via hwc.mail.calendar.radicale.extraCollections), and the MCP's
# hwc_calendar tool. Nothing else needs a copy of the URL.
#
# One-way by design: the `http` storage is read-only, and `partial_sync =
# "revert"` undoes any edit made on the Radicale side (phone, khal) on the next
# run, so the mirror stays a mirror. Edit the event where it lives.
#
# The CRM keeps reading the same feeds itself (hwc.business.crm.calendar
# .busyFeeds): it needs a fresher, fail-closed read for granting a time. This
# unit is for the eyes, that one is for the booking rule.
#
# Secrets never enter the nix store: the vdirsyncer config is written at start
# into RuntimeDirectory (tmpfs, 0700) from the agenix files.
#
# Returns the config fragment only; ../index.nix declares the options.

{ config, lib, pkgs, cfg, htpasswdPath }:

let
  mirrors = cfg.mirrors;
  radicaleUrl = "http://127.0.0.1:${toString cfg.port}";
  secretPath = name: lib.attrByPath [ "age" "secrets" name "path" ] "/run/agenix/${name}" config;

  # The `eric` password, field 2+ of the shared htpasswd secret (colons kept).
  passwordAwk = ''${pkgs.gawk}/bin/awk -F: -v u=${cfg.mirrorUser} '$1==u{match($0,/:/);print substr($0,RSTART+1)}' ${htpasswdPath}'';

  mkcalendarBody = id: m: ''
    <?xml version="1.0" encoding="utf-8" ?>
    <C:mkcalendar xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav" xmlns:ICAL="http://apple.com/ns/ical/">
      <D:set><D:prop>
        <D:displayname>${m.displayName}</D:displayname>
        <ICAL:calendar-color>${m.color}</ICAL:calendar-color>
        <C:supported-calendar-component-set><C:comp name="VEVENT"/></C:supported-calendar-component-set>
      </D:prop></D:set>
    </C:mkcalendar>
  '';

  # vdirsyncer section names allow only [A-Za-z0-9_]; collection ids may use '-'.
  section = id: builtins.replaceStrings [ "-" ] [ "_" ] id;

  perMirror = id: m: ''
    # ---- ${id}: ${m.displayName}
    url=$(tr -d '[:space:]' < ${secretPath m.secret})
    urls+=("$url")
    case "$url" in
      https://*|http://*) ;;
      *) echo "radicale-mirror: secret ${m.secret} does not hold a feed URL" >&2; exit 1 ;;
    esac
    code=$(curl -s -o /dev/null -w '%{http_code}' -u "${cfg.mirrorUser}:$pw" \
             -X PROPFIND -H 'Depth: 0' "${radicaleUrl}/${cfg.mirrorUser}/${id}/")
    if [ "$code" = 404 ]; then
      echo "radicale-mirror: creating collection ${id} (${m.displayName})"
      curl -sf -o /dev/null -u "${cfg.mirrorUser}:$pw" -X MKCALENDAR \
        -H 'Content-Type: application/xml' --data-binary @${pkgs.writeText "mkcalendar-${id}.xml" (mkcalendarBody id m)} \
        "${radicaleUrl}/${cfg.mirrorUser}/${id}/"
    elif [ "$code" != 207 ]; then
      echo "radicale-mirror: Radicale answered $code for ${id}" >&2; exit 1
    fi
    cat >> "$conf" <<EOF

    [pair mirror_${section id}]
    a = "feed_${section id}"
    b = "radicale_${section id}"
    collections = null
    conflict_resolution = "a wins"
    partial_sync = "revert"

    [storage feed_${section id}]
    type = "http"
    url = "$url"

    [storage radicale_${section id}]
    type = "caldav"
    url = "${radicaleUrl}/${cfg.mirrorUser}/${id}/"
    username = "${cfg.mirrorUser}"
    password.fetch = ["command", "cat", "$RUNTIME_DIRECTORY/pw"]
    item_types = ["VEVENT"]
    EOF
  '';

  script = pkgs.writeShellScript "radicale-mirror" ''
    set -euo pipefail
    umask 077
    conf="$RUNTIME_DIRECTORY/config"
    pw=$(${passwordAwk})
    [ -n "$pw" ] || { echo "radicale-mirror: no ${cfg.mirrorUser} line in the htpasswd secret" >&2; exit 1; }
    printf '%s' "$pw" > "$RUNTIME_DIRECTORY/pw"
    printf '[general]\nstatus_path = "%s/status"\n' "$STATE_DIRECTORY" > "$conf"
    urls=()
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList perMirror mirrors)}
    # vdirsyncer names a storage by its URL in some error messages, and the
    # failure notifier forwards the last journal lines to Discord. Every
    # feed URL is replaced before a line reaches the journal.
    redact() {
      ${pkgs.python3}/bin/python3 -c '
    import sys
    urls = [u for u in sys.argv[1:] if u]
    for line in sys.stdin:
        for u in urls:
            line = line.replace(u, "<feed url>")
        sys.stdout.write(line); sys.stdout.flush()
    ' "''${urls[@]}"
    }
    # discover is required once per pair even with collections = null; with
    # nothing to create it never prompts, so it is safe to run every time.
    ${pkgs.vdirsyncer}/bin/vdirsyncer -c "$conf" discover 2>&1 | redact
    ${pkgs.vdirsyncer}/bin/vdirsyncer -c "$conf" sync 2>&1 | redact
    # Feed URLs are secrets: the config dies with the run.
    rm -f "$conf" "$RUNTIME_DIRECTORY/pw"
  '';
in
# Implementation only: the options (mirrors, mirrorUser, mirrorInterval) are
# declared in ../index.nix (Charter Law 10: options live in the unit's index).
lib.mkIf (cfg.enable && mirrors != {}) {
    assertions = map (m: {
      assertion = config.age.secrets ? ${m.secret};
      message = "hwc.server.services.radicale.mirrors: agenix secret '${m.secret}' is not declared.";
    }) (lib.attrValues mirrors);

    systemd.services.radicale-mirror = {
      description = "Mirror outside calendars into Radicale (read-only)";
      after = [ "radicale.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      requires = [ "radicale.service" ];
      path = [ pkgs.curl pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        SupplementaryGroups = [ "secrets" ];
        StateDirectory = "radicale-mirror";
        RuntimeDirectory = "radicale-mirror";
        RuntimeDirectoryMode = "0700";
        ExecStart = script;
        TimeoutStartSec = "5min";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    systemd.timers.radicale-mirror = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitActiveSec = cfg.mirrorInterval;
        RandomizedDelaySec = "1min";
        Persistent = true;
      };
    };
}
