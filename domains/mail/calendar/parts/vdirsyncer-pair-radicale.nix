# domains/mail/calendar/parts/vdirsyncer-pair-radicale.nix
#
# [pair calendar_radicale] + storages for the self-hosted Radicale backend
# (domains/server/services/radicale on hwc-server, fronted by Caddy at
# tasks.hwc.iheartwoodcraft.com — the same vhost also serves VEVENT calendars).
#
# This is the VEVENT twin of domains/mail/tasks/parts/vdirsyncer-pair-radicale.nix
# (which carries VTODO). Same Radicale server, same htpasswd secret; the only
# differences are item_types = ["VEVENT"] and the local storage dir.
#
# Collection scoping: calendar and tasks share ONE Radicale account, and
# vdirsyncer can't filter discovery by component type — so "from a"/"from b"
# would make THIS (VEVENT) pair also grab the tasks_radicale VTODO collections
# (personal/work/family/Reminders) and create empty local dirs for them. We
# therefore pin to the single calendar collection `migrated` (displayname
# "Calendar", created by the one-time iCloud→Radicale migration). Adding another
# calendar = add its collection id here. (A fully clean separation would give
# calendar its own Radicale principal; explicit scoping is the pragmatic fix.)
# The password is field 2+ of the agenix htpasswd secret shared with the server.

{ url, username, secretPath, dataDir }:

''
  [pair calendar_radicale]
  a = "calendar_radicale_remote"
  b = "calendar_radicale_local"
  collections = ["migrated"]
  metadata = ["displayname", "color"]
  # Local wins: Radicale auto-names a collection at MKCALENDAR, which would
  # otherwise MetaSyncConflict against the real name on the first metasync
  # (and khal/local is the authoring side for calendar names anyway).
  conflict_resolution = "b wins"

  [storage calendar_radicale_remote]
  type = "caldav"
  url = "${url}"
  username = "${username}"
  # Run cut directly (no `sh -c`): the vdirsyncer service PATH carries coreutils
  # but NOT bash, so `sh` isn't found — and the shell wrapper buys nothing here.
  # Mirrors the iCloud pair's direct `["command", "cat", …]`. Emits field 2+ of
  # the htpasswd line (user:password) = the password.
  password.fetch = ["command", "cut", "-d:", "-f2-", "${secretPath}"]
  item_types = ["VEVENT"]

  [storage calendar_radicale_local]
  type = "filesystem"
  path = "${dataDir}/calendars-radicale/"
  fileext = ".ics"
''
