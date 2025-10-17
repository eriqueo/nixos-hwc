{ lib, pkgs, config, ... }:

let
  data = import ./data.nix { };

  tagsPrefs = pkgs.writeText "bb-tags.js" (lib.concatStringsSep "\n" (map
    (t: ''
      user_pref("mailnews.tags.${lib.replaceStrings [" "] ["_"] t.name}.tag", "${t.name}");
      user_pref("mailnews.tags.${lib.replaceStrings [" "] ["_"] t.name}.color", "${t.color}");
      user_pref("mailnews.tags.${lib.replaceStrings [" "] ["_"] t.name}.ordinal", ${toString (t.ordinal or 99)});
    '')
    data.tags));

  filtersTemplate = pkgs.writeText "bb-msgFilterRules.dat" data.filtersDat;

  importer = pkgs.writeShellScriptBin "bb-apply-mail-data" ''
    set -euo pipefail

    PROF_INI="$HOME/.betterbird/profiles.ini"
    [ -f "$PROF_INI" ] || exit 0

    # Get the default profile path (Path= when Default=1)
    PROFILE_PATH=$(awk -F= '
      /^\[Profile/ {d=0}
      /^Default=1/ {d=1}
      d==1 && /^Path=/ {print $2; exit}
    ' "$PROF_INI")

    [ -n "''${PROFILE_PATH:-}" ] || exit 0
    case "$PROFILE_PATH" in
      /*) PROFILE_DIR="$PROFILE_PATH" ;;
      *)  PROFILE_DIR="$HOME/.betterbird/$PROFILE_PATH" ;;
    esac
    [ -d "$PROFILE_DIR" ] || exit 0

    # ---- Tags: append into prefs.js idempotently (won’t fight HM’s user.js)
    PREFS="$PROFILE_DIR/prefs.js"
    mkdir -p "$PROFILE_DIR"
    touch "$PREFS"

    START="// HWC: tags begin"
    END="// HWC: tags end"
    awk -v start="$START" -v end="$END" '
      BEGIN{skip=0}
      $0==start {skip=1; next}
      $0==end   {skip=0; next}
      skip==0   {print}
    ' "$PREFS" > "$PREFS.tmp" && mv "$PREFS.tmp" "$PREFS"

    {
      echo "$START"
      cat "${tagsPrefs}"
      echo "$END"
    } >> "$PREFS"

    # ---- Filters: copy/merge to each account rules file
    for BASE in "$PROFILE_DIR/ImapMail" "$PROFILE_DIR/Mail"; do
      [ -d "$BASE" ] || continue
      for ACC in "$BASE"/*; do
        [ -d "$ACC" ] || continue
        RULES="$ACC/msgFilterRules.dat"

        if [ ! -f "$RULES" ]; then
          install -Dm0644 "${filtersTemplate}" "$RULES"
        else
          # Idempotent append under a marker
          if ! grep -q "HWC: filters injected" "$RULES"; then
            {
              echo ""
              echo "# HWC: filters injected"
              cat "${filtersTemplate}"
            } >> "$RULES"
          fi
        fi
      done
    done
  '';
in
{
  packages = [ importer ];

  services = {
    # Run once per login; safe to re-run (idempotent markers).
    "betterbird-import-mail-data" = {
      Unit = {
        Description = "Apply Betterbird tags and filters to default profile";
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${importer}/bin/bb-apply-mail-data";
      };
      Install = { WantedBy = [ "default.target" ]; };
    };
  };

  # No files from tools; it mutates user-owned prefs.js / per-account filter files.
  env = {};
}
