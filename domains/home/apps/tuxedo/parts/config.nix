# domains/home/apps/tuxedo/parts/config.nix
#
# Seed contents for ~/.config/tuxedo/config.toml.
#
# IMPORTANT: tuxedo OWNS this file at runtime. Cycling theme/density/sort,
# toggling sidebars / line-numbers / done-visibility, saving searches
# (filter.<n> = <query>), and the phone-capture server (share_token /
# share_port) all rewrite config.toml. It must therefore remain a normal
# WRITABLE file — never a home-manager xdg.configFile store symlink, which
# would make tuxedo's own writes fail. index.nix seeds this once (only if the
# file is absent) via home.activation; tuxedo manages it thereafter.
#
# The todo.txt / done.txt locations are NOT set here — they come from the
# TODO_DIR / TODO_FILE / DONE_FILE environment variables (todo.txt-cli
# convention) set in index.nix.

{ }:

''
  # tuxedo configuration.
  #
  # Seeded by NixOS (hwc.home.apps.tuxedo). tuxedo rewrites this file at runtime
  # to persist UI state (theme, density, sort order, sidebars, saved searches).
  # Safe to hand-edit while tuxedo is not running.
  #
  # share_token is a secret once written by the phone-capture server: anyone
  # with that value and LAN reach can append to your inbox. Do not commit it.
''
