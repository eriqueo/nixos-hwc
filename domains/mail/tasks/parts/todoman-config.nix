# domains/mail/tasks/parts/todoman-config.nix
#
# Returns the text of ~/.config/todoman/config.py. todoman's config is
# executable Python with module-level variables (read from todoman 4.7.0).
# A read-only store symlink is fine — todoman does not rewrite this file.

{ defaultList, pathGlob ? "tasks/*" }:

''
  # Glob over vdirsyncer's tasks vdir(s): one subdir per remote list.
  # "tasks*/*" also covers tasks-radicale/ when that backend is enabled.
  path = "~/.local/share/vdirsyncer/${pathGlob}"

  # Default list for `todo new` when -l is omitted. NOTE: this must match a
  # collection directory name created by `vdirsyncer discover tasks`. If the
  # discovered list name differs (e.g. "Reminders" vs a localized name), update
  # this value and re-run `hms`. See README go/no-go step 8.
  default_list = "${defaultList}"

  date_format = "%Y-%m-%d"
  time_format = "%H:%M"
  default_due = 0
  cache_path = "~/.cache/todoman/cache.sqlite3"
''
