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

  defaultCal = lib.head (lib.attrNames cfg.accounts);
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
    default_calendar = ${defaultCal}
    highlight_event_days = true

    [view]
    theme = dark
  '';
}
