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
  '';
}
