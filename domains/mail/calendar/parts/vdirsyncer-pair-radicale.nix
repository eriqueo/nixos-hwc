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
# Collections use "from a"/"from b" discovery: Radicale allows collection
# creation (MKCALENDAR), so calendars created locally (khal/ikhal `new`) are
# created server-side on the next `vdirsyncer discover calendar_radicale` +
# sync, and calendars created on the server/phone appear locally. The password
# is the second field of the agenix htpasswd secret shared with the server.

{ url, username, secretPath, dataDir }:

''
  [pair calendar_radicale]
  a = "calendar_radicale_remote"
  b = "calendar_radicale_local"
  collections = ["from a", "from b"]
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
