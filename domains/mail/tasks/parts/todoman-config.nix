# domains/mail/tasks/parts/todoman-config.nix
#
# Returns the text of ~/.config/todoman/config.py. todoman's config is
# executable Python with module-level variables (read from todoman 4.7.0).
# A read-only store symlink is fine — todoman does not rewrite this file.

{ defaultList }:

''
  # Glob over the tasks_radicale vdir: one subdir per Radicale collection.
  path = "~/.local/share/vdirsyncer/tasks-radicale/*"

  # Default list for `todo new` when -l is omitted. todoman matches the
  # collection's displayname (case-insensitive), not its directory name.
  default_list = "${defaultList}"

  date_format = "%Y-%m-%d"
  time_format = "%H:%M"
  default_due = 0
  cache_path = "~/.cache/todoman/cache.sqlite3"
''
