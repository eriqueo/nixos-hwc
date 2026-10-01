# domains/mail/calendar/parts/ics-watcher.nix
# Pure function — returns HM systemd attrs for .ics auto-import
#
# Two folders: Downloads (files Eric saves; imported ones move to events/) and
# the private calendar drop (programs such as event-scout; imported ones move
# to imported/, which event-scout reads as "added").
{ lib, pkgs, khal, dropDir }:

let
  importScript = pkgs.writeShellScript "khal-import-ics" ''
    set -euo pipefail
    shopt -s nullglob
    IMPORTED=0

    import_dir() { # import_dir <inbox> <done>
      mkdir -p "$2"
      for f in "$1"/*.ics; do
        echo "[khal-import] Importing: $f"
        if ${khal}/bin/khal import --batch "$f"; then
            mv "$f" "$2/"
            IMPORTED=$((IMPORTED + 1))
        else
            echo "[khal-import] Failed to import: $f - leaving in place"
        fi
      done
    }

    import_dir "$HOME/000_inbox/downloads" "$HOME/000_inbox/downloads/events"
    import_dir ${lib.escapeShellArg dropDir} ${lib.escapeShellArg "${dropDir}/imported"}

    if [ "$IMPORTED" -gt 0 ]; then
        echo "[khal-import] Syncing $IMPORTED event(s) to Radicale via vdirsyncer..."
        ${pkgs.vdirsyncer}/bin/vdirsyncer sync
        echo "[khal-import] Done."
    else
        echo "[khal-import] No new .ics files found."
    fi
  '';
in
{
  systemd.user.services.khal-import-ics = {
    Unit.Description = "Import .ics files from downloads and the calendar drop into khal";
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
    Unit.Description = "Watch ~/000_inbox/downloads and the calendar drop for .ics files";
    Path = {
      PathChanged = [ "%h/000_inbox/downloads" dropDir ];
      Unit = "khal-import-ics.service";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
