# domains/mail/tasks/parts/vdirsyncer-pair.nix
#
# Returns the [pair tasks] + [storage …] fragment for the shared vdirsyncer
# config. Contributed to hwc.mail.calendar.extraVdirsyncerPairs so there is a
# single vdirsyncer config file and a single sync timer.
#
# The `item_types = ["VTODO"]` line is the knob that makes CalDAV expose Apple
# Reminders (VTODO) collections instead of calendars (VEVENT).

{ email, applePwPath, dataDir }:

''
  [pair tasks]
  a = "tasks_remote"
  b = "tasks_local"
  collections = ["from a", "from b"]
  metadata = ["displayname"]

  [storage tasks_remote]
  type = "caldav"
  url = "https://caldav.icloud.com/"
  username = "${email}"
  password.fetch = ["command", "cat", "${applePwPath}"]
  item_types = ["VTODO"]

  [storage tasks_local]
  type = "filesystem"
  path = "${dataDir}/tasks/"
  fileext = ".ics"
''
