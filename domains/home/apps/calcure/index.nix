# domains/home/apps/calcure/index.nix
#
# calcure — Modern TUI calendar and task manager (Python, customizable UI)
# Config: ~/.config/calcure/config.ini
# Theme: terminal color indices mapped to Nord palette via kitty's ANSI assignments
#
# Nord → terminal color index mapping (from kitty config):
#   1 = terminal red     (error/crit)
#   2 = terminal green   (success/done)
#   3 = terminal yellow  (warning)
#   4 = terminal blue    (primary accent)
#   5 = terminal magenta (accent alt)
#   6 = terminal cyan    (secondary accent)
#   7 = terminal white   (foreground)
#  -1 = transparent (preserves terminal background)
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.calcure;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.calcure = {
    enable = lib.mkEnableOption "calcure modern TUI calendar and task manager";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.calcure ];

    xdg.desktopEntries.calcure = {
      name = "calcure";
      comment = "Modern TUI calendar and task manager";
      exec = "kitty --title calcure calcure";
      terminal = false;
      categories = [ "Office" "Calendar" ];
    };

    xdg.configFile."calcure/config.ini".text = ''
      [general]
      show_keybindings = yes
      start_week_day = 1
      show_day_names = yes
      minimal_today_indicator = yes
      minimal_days_indicator = yes
      minimal_weekend_indicator = yes
      use_unicode_icons = yes
      show_hours = yes
      show_minutes = yes
      ask_before_quit = no
      show_header = yes
      header_text = CALCURE

      [appearance]
      bold_today = yes
      bold_title = yes
      minimal_today = no

      [colors]
      # Today highlight → terminal blue (slot 4 — palette ansi.blue via kitty)
      color_today = 4
      # General text → terminal white (palette ansi.white via kitty)
      color_events = 7
      color_days = 7
      color_time = 7
      color_hints = 7
      # Day names / calendar header → terminal cyan
      color_day_names = 6
      color_calendar_header = 6
      color_separator = 6
      color_calendar_border = 6
      # Weekends → terminal yellow — notable but not alarming
      color_weekends = 3
      color_weekend_names = 3
      # Prompts and confirmations → primary accent / red
      color_prompts = 4
      color_confirmations = 1
      # Special dates
      color_birthdays = 5
      color_holidays = 2
      color_deadlines = 1
      # Tasks
      color_todo = 7
      color_done = 2
      # Title → terminal blue
      color_title = 4
      # Status/priority
      color_important = 1
      color_unimportant = 6
      # Timer
      color_timer = 2
      color_timer_paused = 7
      # Active pane border → terminal blue
      color_active_pane = 4
      # Transparent background (inherits the terminal theme bg)
      color_background = -1
    '';

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [];
  };
}
