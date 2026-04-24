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

    IMPORTED=0
    for f in "$INBOX"/*.ics; do
      echo "[khal-import] Importing: $f"
      if ${pkgs.khal}/bin/khal import --batch "$f"; then
          mv "$f" "$DONE/"
          IMPORTED=$((IMPORTED + 1))
      else
          echo "[khal-import] Failed to import: $f - leaving in place"
      fi
    done
    
    if [ "$IMPORTED" -gt 0 ]; then
        echo "[khal-import] Syncing $IMPORTED event(s) to iCloud via vdirsyncer..."
        ${pkgs.vdirsyncer}/bin/vdirsyncer sync
        echo "[khal-import] Done."
    else
        echo "[khal-import] No new .ics files found."
    fi
  '';
in
{
  systemd.user.services.khal-import-ics = {
    Unit.Description = "Import .ics files from downloads into khal";
    Service = {
      Type = "oneshot";
      Environment = [
        "HOME=%h"
        "PATH=${pkgs.coreutils}/bin"
      ];
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
