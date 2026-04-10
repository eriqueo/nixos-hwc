# domains/mail/calendar/parts/ics-watcher.nix
# Pure function — returns HM systemd attrs for .ics auto-import
{ lib, pkgs }:

let
  importScript = pkgs.writeShellScript "khal-import-ics" ''
    set -euo pipefail
    INBOX="$HOME/000_inbox/downloads"
    DONE="$HOME/000_inbox/downloads/events"
    mkdir -p "$DONE"

    shopt -s nullglob
    for f in "$INBOX"/*.ics; do
      echo "[khal-import] Importing: $f"
      ${pkgs.khal}/bin/khal import --batch "$f" && mv "$f" "$DONE/"
    done
  '';
in
{
  systemd.user.services.khal-import-ics = {
    Unit.Description = "Import .ics files from downloads into khal";
    Service = {
      Type = "oneshot";
      ExecStart = "${importScript}";
    };
  };

  systemd.user.paths.khal-import-ics = {
    Unit.Description = "Watch ~/000_inbox/downloads for .ics files";
    Path = {
      PathChanged = "%h/000_inbox/downloads";
      Unit = "khal-import-ics.service";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
