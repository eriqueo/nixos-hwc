# modules/home/apps/dunst/parts/appearance.nix
{ config, lib, pkgs, ... }:

let
  palette = config.theme.palette or {};
in
{
  settings = {
    global = {
      width = 300;
      height = 300;
      offset = "30x50";
      origin = "top-right";
      transparency = 10;
      frame_width = 2;
      frame_color = palette.accent or "#88c0d0";
      separator_color = "frame";
      font = "JetBrains Mono 10";
      line_height = 0;
      markup = "full";
      format = "<b>%s</b>\\n%b";
      alignment = "left";
      vertical_alignment = "center";
      show_age_threshold = 60;
      word_wrap = true;
      ellipsize = "middle";
      ignore_newline = false;
      stack_duplicates = true;
      hide_duplicate_count = false;
      show_indicators = true;
      icon_position = "left";
      max_icon_size = 32;
      icon_path = "/usr/share/icons/gnome/16x16/status/:/usr/share/icons/gnome/16x16/devices/";
      sticky_history = true;
      history_length = 20;
      browser = "${pkgs.xdg-utils}/bin/xdg-open";
      always_run_script = true;
      title = "Dunst";
      class = "Dunst";
      corner_radius = 8;
      ignore_dbusclose = false;
      force_xwayland = false;
      force_xinerama = false;
      mouse_left_click = "close_current";
      mouse_middle_click = "do_action, close_current";
      mouse_right_click = "close_all";
    };

    experimental = {
      per_monitor_dpi = false;
    };

    urgency_low = {
      background = palette.surface or "#2e3440";
      foreground = palette.text or "#d8dee9";
      timeout = 10;
    };

    urgency_normal = {
      background = palette.surface or "#2e3440";
      foreground = palette.text or "#d8dee9";
      timeout = 10;
    };

    urgency_critical = {
      background = palette.urgent or "#bf616a";
      foreground = palette.background or "#eceff4";
      frame_color = palette.urgent or "#bf616a";
      timeout = 0;
    };
  };
}