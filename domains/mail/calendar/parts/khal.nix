# domains/mail/calendar/parts/khal.nix  — PALETTE-DRIVEN VARIANT (staged)
#
# WHAT CHANGED vs the in-repo khal.nix:
#   The `[palette]` section was hardcoded Gruvbox-Material hex (e.g. '#d4be98',
#   '#32302f', '#a9b665'...). That defeats the system-theme contract: switching
#   hwc.home.theme.palette left khal stuck on gruvbox. This variant DERIVES the
#   palette from the active theme tokens, exactly like yazi/tasq/workbench.
#
# HOW THE TOKENS REACH HERE:
#   khal.nix is imported by domains/mail/calendar/index.nix with
#   `import ./parts/khal.nix { inherit lib pkgs cfg; }`. The system theme lives
#   at config.hwc.home.theme.colors. So index.nix must ALSO pass `colors`:
#     khalConfig = import ./parts/khal.nix {
#       inherit lib pkgs cfg;
#       colors = (config.hwc.home.theme or {}).colors or {};
#     };
#   (calendar is a mail/ domain module evaluated in the HM lane, so
#   config.hwc.home.theme is in scope — same as how tasq reads it.)
#
# This keeps khal's urwid palette grammar intact (named-color fallback in
# positions 1-2, 24-bit hex in positions 4-5); only the hex literals become
# token lookups.

{ lib, pkgs, cfg, colors ? {} }:
let
  dataDir = "~/.local/share/vdirsyncer";

  # Fail-soft: no theme -> fall back to the original gruvbox literals so a
  # bare eval still produces a valid config (boundary recovery).
  c = colors;
  hex = name: fallback: "'#${c.${name} or fallback}'";

  mkCalendar = name: acc: ''
    [[${name}]]
    path = ${dataDir}/calendars/${name}/*
    color = ${acc.color}
    type = discover
  '';

  mkLocalCalendar = name: local: ''
    [[${name}]]
    path = ${local.path}
    color = ${local.color}
    type = discover
  '';

  # Radicale-synced calendars (VEVENT) discovered under calendars-radicale/.
  # When the Radicale backend is on, the iCloud accounts no longer generate
  # vdirsyncer pairs, so this is the live calendar source.
  radicaleCalendar = lib.optionalString cfg.radicale.enable ''
    [[radicale]]
    path = ${dataDir}/calendars-radicale/*
    color = ${cfg.radicale.color}
    type = discover
  '';

  # When Radicale is the backend, iCloud account pairs are not synced, so their
  # stale calendars/<account>/ dirs are not surfaced (mirrors vdirsyncer.nix).
  accountCalendars = lib.optionals (!cfg.radicale.enable)
    (lib.mapAttrsToList mkCalendar cfg.accounts);

  calendars = lib.concatStringsSep "\n" (
    accountCalendars
    ++ (lib.mapAttrsToList mkLocalCalendar (cfg.localCalendars or {}))
    ++ lib.optional (radicaleCalendar != "") radicaleCalendar
  );

  # --- palette role -> (named fallback, hi-color token) -----------------------
  # Positions: foreground, background, mono, foreground_high, background_high
  # Only the hi-color (4th/5th) fields are theme-driven; the urwid named-color
  # fallbacks (1st/2nd) stay literal so 16-color terminals still render.
in
{
  config = ''
    [calendars]
    ${calendars}

    [locale]
    timeformat = %H:%M
    dateformat = %Y-%m-%d
    longdateformat = %Y-%m-%d %A
    datetimeformat = %Y-%m-%d %H:%M
    longdatetimeformat = %Y-%m-%d %H:%M %A

    [default]
    ${if cfg.radicale.enable
      then "default_calendar = migrated"   # the one calendar availability reads
      else "default_calendar = 06A30686-742B-4681-BBE9-BB15C7E9A54F"}
    highlight_event_days = true

    [view]
    theme = dark
    # Strip HTML descriptions from Apple Calendar events; keep title + time only
    agenda_event_format = {calendar-color}{cancelled}{start-end-time-style} {title}{repeat-symbol}{alarm-symbol}{reset}
    blank_line_before_day = true
    event_view_weighting = 2
    frame = top

    [palette]
    # Format: foreground, background, mono, foreground_high, background_high
    # Positions 1-2: named urwid colors (low-color fallback)
    # Positions 4-5: 24-bit hex from the active system theme (was hardcoded gruvbox)
    header              = white,      black,       bold,    ${hex "fg1" "d4be98"}, ${hex "surface0" "32302f"}
    footer              = light gray, black,       bold,    ${hex "fg3" "928374"}, ${hex "surface0" "32302f"}
    line header         = black,      light cyan,  bold,    ${hex "bg0" "32302f"}, ${hex "accent" "7daea3"}
    today               = black,      light green, bold,    ${hex "bg0" "32302f"}, ${hex "success" "a9b665"}
    today focus         = black,      dark cyan,   bold,    ${hex "bg0" "32302f"}, ${hex "accent" "7daea3"}
    date header         = dark gray,  black,       default, ${hex "fg3" "7c6f64"}, ${hex "surface0" "32302f"}
    date header focused = white,      dark gray,   bold,    ${hex "fg1" "d4be98"}, ${hex "bg2" "3c3836"}
    date header selected= light gray, dark gray,   default, ${hex "fg2" "928374"}, ${hex "bg3" "504945"}
    dayname             = light gray, black,       default, ${hex "fg2" "928374"}, ${hex "surface0" "32302f"}
    monthname           = yellow,     black,       bold,    ${hex "warning" "d8a657"}, ${hex "surface0" "32302f"}
    reveal focus        = black,      yellow,      bold,    ${hex "bg0" "32302f"}, ${hex "warning" "d8a657"}
    mark                = black,      light magenta,bold,   ${hex "bg0" "32302f"}, ${hex "marked" "d3869b"}
    alert               = white,      dark red,    bold,    ${hex "bg0" "32302f"}, ${hex "error" "ea6962"}
    button              = black,      dark cyan,   default, ${hex "bg0" "32302f"}, ${hex "accent2" "89b482"}
    button focused      = black,      light cyan,  bold,    ${hex "bg0" "32302f"}, ${hex "accent" "7daea3"}
  '';
}
