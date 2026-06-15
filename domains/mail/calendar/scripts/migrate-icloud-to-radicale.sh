#!/usr/bin/env bash
# domains/mail/calendar/scripts/migrate-icloud-to-radicale.sh
#
# ONE-TIME calendar migration: iCloud (CalDAV) → self-hosted Radicale.
#
# Mirrors the tasks migration (iCloud VTODO → Radicale, 2026-06-11). It copies
# the existing iCloud VEVENT .ics files out of the legacy vdirsyncer iCloud
# vdir into a single local Radicale collection dir, which `vdirsyncer sync
# calendar_radicale` then uploads to the server.
#
# ─────────────────────────────────────────────────────────────────────────────
# RUN THIS ON THE LAPTOP, ONCE, AFTER:
#   1. The server is deployed with hwc.server.services.radicale (already live —
#      it hosts the tasks backend) and the radicale-htpasswd secret exists.
#   2. `hms` has run with hwc.mail.calendar.radicale.enable = true so that
#      ~/.config/vdirsyncer/config contains the [pair calendar_radicale] block
#      and ~/.local/share/vdirsyncer/calendars-radicale/ exists.
#   3. The legacy iCloud calendar vdir is still present (it is NOT deleted by
#      enabling radicale — vdirsyncer just stops generating the iCloud pair):
#        ~/.local/share/vdirsyncer/calendars/icloud/<collection>/*.ics
#
# This script does NOT delete anything. It is idempotent for re-runs (skips
# files already present in the target by filename).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

VDIR="${HOME}/.local/share/vdirsyncer"
SRC_ROOT="${VDIR}/calendars/icloud"           # legacy iCloud calendar vdir
DEST_COLLECTION="${VDIR}/calendars-radicale/migrated"  # one local Radicale collection

if [ ! -d "$SRC_ROOT" ]; then
  echo "ERROR: source iCloud calendar dir not found: $SRC_ROOT" >&2
  echo "Nothing to migrate (was the calendar already moved, or never iCloud-synced?)." >&2
  exit 1
fi

mkdir -p "$DEST_COLLECTION"

echo "Copying iCloud VEVENT .ics files → $DEST_COLLECTION"
copied=0 skipped=0
# iCloud layout: calendars/icloud/<collection>/<uid>.ics — flatten all
# collections into one Radicale collection. UIDs are globally unique, so file
# basenames don't collide across iCloud calendars in practice; if two do, the
# second is renamed to keep both.
while IFS= read -r -d '' f; do
  base="$(basename "$f")"
  dest="${DEST_COLLECTION}/${base}"
  if [ -e "$dest" ]; then
    # Already migrated (re-run) OR genuine basename collision — disambiguate.
    if cmp -s "$f" "$dest"; then
      skipped=$((skipped + 1)); continue
    fi
    dest="${DEST_COLLECTION}/$(basename "$f" .ics)-$(date +%s%N).ics"
  fi
  cp -n "$f" "$dest" && copied=$((copied + 1))
done < <(find "$SRC_ROOT" -type f -name '*.ics' -print0)

echo "Copied $copied file(s), skipped $skipped already-present."

# A vdirsyncer filesystem collection needs a displayname so Radicale shows a
# friendly name (and so metasync doesn't fight the auto-name on first push).
if [ ! -f "${DEST_COLLECTION}/displayname" ]; then
  printf 'Calendar' > "${DEST_COLLECTION}/displayname"
fi

cat <<'EOF'

Local import complete. Now push to Radicale:

  # 1. Discover — answer 'y' to create the 'migrated' collection on the server
  #    (Radicale MKCALENDAR) and register the existing tasks_radicale collection.
  vdirsyncer discover calendar_radicale

  # 2. Upload the events.
  vdirsyncer sync calendar_radicale

  # 3. Verify locally:
  khal list today 90d        # khalt's khal, reading ~/.config/khal/config
  # …and on the server:
  ls /var/lib/radicale/collections/collection-root/eric/

  # 4. (Phone) add a CalDAV *Calendar* account — server
  #    tasks.hwc.iheartwoodcraft.com, user eric, the radicale-htpasswd password.

Once verified, the legacy iCloud vdir can be archived (it is no longer synced):

  mv ~/.local/share/vdirsyncer/calendars/icloud \
     ~/.local/share/vdirsyncer/archive-icloud-calendars-$(date +%F)
EOF
