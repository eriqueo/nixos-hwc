{ lib, pkgs, cfg, applePwPath, radicalePair ? "" }:
let
  dataDir = "~/.local/share/vdirsyncer";

  mkPair = name: acc: ''
    [pair ${name}]
    a = "${name}_remote"
    b = "${name}_local"
    # Server-authoritative discovery ("from a" only): iCloud can't create
    # calendars over CalDAV, so a local-only collection (e.g. a calendar deleted
    # on iCloud, or a dead Reminders list orphaned by Apple's 2026-06 Reminders
    # change) can never sync up — it 404s every run and aborts the whole sync.
    # "from a" simply ignores such stale local dirs (no data deleted).
    collections = ["from a"]
    metadata = ["color", "displayname"]

    [storage ${name}_remote]
    type = "caldav"
    url = "https://caldav.icloud.com/"
    username = "${acc.email}"
    password.fetch = ["command", "cat", "${applePwPath}"]

    [storage ${name}_local]
    type = "filesystem"
    path = "${dataDir}/calendars/${name}/"
    fileext = ".ics"
  '';

  # iCloud account pairs are retired when the Radicale backend is on: the
  # calendar then lives on the self-hosted server (calendar_radicale below),
  # exactly like the tasks backend. With radicale off, the legacy iCloud
  # accounts still generate their pairs.
  pairs = lib.optionalString (!cfg.radicale.enable)
    (lib.concatStringsSep "\n" (lib.mapAttrsToList mkPair cfg.accounts));

  # Pairs contributed by sibling modules (e.g. mail/tasks → VTODO/Reminders).
  # Kept in the same config so vdirsyncer has one config file + one timer.
  extraPairs = lib.concatStringsSep "\n" cfg.extraVdirsyncerPairs;
in
{
  config = ''
    [general]
    status_path = "${dataDir}/status/"

    ${pairs}
    ${radicalePair}
    ${extraPairs}
  '';
}
