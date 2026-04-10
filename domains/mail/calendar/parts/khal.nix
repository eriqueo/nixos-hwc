{ lib, pkgs, cfg }:
let
  dataDir = "~/.local/share/vdirsyncer";

  mkCalendar = name: acc: ''
    [[${name}]]
    path = ${dataDir}/calendars/${name}/*
    color = ${acc.color}
    type = discover
  '';

  calendars = lib.concatStringsSep "\n" (lib.mapAttrsToList mkCalendar cfg.accounts);
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
    default_calendar = 06A30686-742B-4681-BBE9-BB15C7E9A54F
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
    # Positions 4-5: 24-bit hex (high-color terminals)
    header              = white,      black,       bold,    '#d4be98', '#32302f'
    footer              = light gray, black,       bold,    '#928374', '#32302f'
    line header         = black,      light cyan,  bold,    '#32302f', '#7daea3'
    today               = black,      light green, bold,    '#32302f', '#a9b665'
    today focus         = black,      dark cyan,   bold,    '#32302f', '#7daea3'
    date header         = dark gray,  black,       default, '#7c6f64', '#32302f'
    date header focused = white,      dark gray,   bold,    '#d4be98', '#3c3836'
    date header selected= light gray, dark gray,   default, '#928374', '#504945'
    dayname             = light gray, black,       default, '#928374', '#32302f'
    monthname           = yellow,     black,       bold,    '#d8a657', '#32302f'
    reveal focus        = black,      yellow,      bold,    '#32302f', '#d8a657'
    mark                = black,      light magenta,bold,   '#32302f', '#d3869b'
    alert               = white,      dark red,    bold,    '#32302f', '#ea6962'
    button              = black,      dark cyan,   default, '#32302f', '#89b482'
    button focused      = black,      light cyan,  bold,    '#32302f', '#7daea3'
  '';
}
