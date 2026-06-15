# domains/mail/tasks/parts/vdirsyncer-pair-radicale.nix
#
# [pair tasks_radicale] + storages for the self-hosted Radicale backend
# (domains/server/services/radicale on hwc-server, fronted by Caddy at
# tasks.hwc.iheartwoodcraft.com).
#
# Unlike the iCloud pair, collections use "from a"/"from b" discovery: Radicale
# allows collection creation (MKCALENDAR), so lists created locally (todui `N`)
# are created server-side on the next `vdirsyncer discover tasks_radicale` +
# sync, and lists created on the server/phone appear locally. The password is
# the second field of the agenix htpasswd secret shared with the server.

{ url, username, secretPath, dataDir }:

''
  [pair tasks_radicale]
  a = "tasks_radicale_remote"
  b = "tasks_radicale_local"
  collections = ["from a", "from b"]
  metadata = ["displayname", "color"]
  # Local wins: Radicale auto-names a collection at MKCALENDAR, which would
  # otherwise MetaSyncConflict against the real name on the first metasync
  # (and todui/local is the authoring side for list names anyway).
  conflict_resolution = "b wins"

  [storage tasks_radicale_remote]
  type = "caldav"
  url = "${url}"
  username = "${username}"
  # Extract THIS user's password from the (now multi-user) htpasswd by username:
  # the calendar backend added a `cal:` line, so a bare `cut -f2-` would emit
  # every line. awk picks the `${username}:…` line and prints everything after
  # the first colon (colon-safe). Quote-free program; runs directly (no shell) —
  # gawk is on the vdirsyncer service PATH (calendar parts/service.nix).
  password.fetch = ["command", "awk", "-F:", "-v", "u=${username}", "$1==u{match($0,/:/);print substr($0,RSTART+1)}", "${secretPath}"]
  item_types = ["VTODO"]

  [storage tasks_radicale_local]
  type = "filesystem"
  path = "${dataDir}/tasks-radicale/"
  fileext = ".ics"
''
