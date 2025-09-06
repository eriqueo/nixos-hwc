# Waybar Part: Style
# Defines the CSS for theming the bar.
{ lib, pkgs, ... }:

let
  ## Read the generated CSS variables from the option provided by the adapter.
  cssVars = config.hwc.home.theme.adapters.waybar.css;
in
# Return the full CSS content as a string.
cssVars + ''
  /* Extra rules that rely on @background/@colorN now work */

  /* Larger font size for laptop monitor */
  window#waybar.eDP-1 * { font-size: 18px; }

  window#waybar {
    background-color: @background;
    color: @foreground;
  }

  #workspaces button {
    padding: 0 5px;
    background-color: transparent;
    color: @foreground;
    border-bottom: 2px solid transparent;
  }
  #workspaces button.active {
    color: @accent;
    border-bottom: 2px solid @accent;
  }
  #workspaces button.urgent {
    color: @crit;
    border-bottom: 2px solid @crit;
  }

  #mode {
    background-color: @accent;
    color: @background;
    border-radius: 5px;
    padding: 0 10px;
    margin: 0 5px;
  }

  #window { padding: 0 10px; }

  #cpu, #memory, #temperature, #disk, #network, #pulseaudio,
  #battery, #clock, #custom-gpu, #idle_inhibitor, #mpd, #tray,
  #custom-notification, #custom-power {
    padding: 0 10px;
    margin: 0 5px;
    color: @foreground;
  }

  #cpu { background-color: @color14; }
  #memory { background-color: @color13; }
  #temperature { background-color: @color12; }
  #disk { background-color: @color11; }
  #network { background-color: @color10; }
  #pulseaudio { background-color: @color9; }
  #battery { background-color: @color8; }
  #clock { background-color: @color7; }
  #custom-gpu { background-color: @color6; }
  #idle_inhibitor { background-color: @color5; }
  #mpd { background-color: @color4; }
  #tray { background-color: @color3; }
  #custom-notification { background-color: @color2; }
  #custom-power { background-color: @color1; }

  /* Specific styles for custom modules based on their class */
  .intel { color: @color4; }
  .nvidia { color: @color2; }
  .performance { color: @color1; }
  .disconnected { color: @error; }
  .excellent { color: @success; }
  .good { color: @info; }
  .fair { color: @warning; }
  .poor { color: @error; }
  .charging { color: @success; }
  .full { color: @success; }
  .high { color: @info; }
  .medium { color: @warning; }
  .low { color: @error; }
  .critical { color: @error; }
''
