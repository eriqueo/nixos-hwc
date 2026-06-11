# domains/mail/tasks/parts/vdirsyncer-pair.nix
#
# Returns the [pair tasks] + [storage …] fragment for the shared vdirsyncer
# config. Contributed to hwc.mail.calendar.extraVdirsyncerPairs so there is a
# single vdirsyncer config file and a single sync timer.
#
# The `item_types = ["VTODO"]` line is the knob that makes CalDAV sync only Apple
# Reminders (VTODO) items, not calendar (VEVENT) items. Note: it filters ITEMS at
# sync time, NOT collection discovery — vdirsyncer has no component filter for
# discovery, so `collections = ["from a","from b"]` would pull every calendar too
# (and break todoman on duplicate display names). Pin `collections` to the VTODO
# collection IDs instead (see hwc.mail.tasks.collections; discover them with
# `vdirsyncer discover tasks` + a supported-calendar-component-set PROPFIND).

{ email, applePwPath, dataDir, collections }:

''
  [pair tasks]
  a = "tasks_remote"
  b = "tasks_local"
  collections = ${builtins.toJSON collections}
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
