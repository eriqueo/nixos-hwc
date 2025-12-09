{ config, lib, pkgs, ... }:
let
  # Use the active theme from central configuration
  palette = config.hwc.home.theme.colors;
in
''
/* Generated from ${palette.name} palette */
window#waybar {
  background-color: #${palette.bg};
  color: #${palette.fg};
}

#workspaces button {
  padding: 0 5px;
  background-color: transparent;
  color: #${palette.fg};
  border-bottom: 2px solid transparent;
}

#workspaces button.active {
  color: #${palette.accent};
  border-bottom: 2px solid #${palette.accent};
}

#workspaces button.urgent {
  color: #${palette.crit};
  border-bottom: 2px solid #${palette.crit};
}

#mode {
  background-color: #${palette.accent};
  color: #${palette.bg};
  border-radius: 5px;
  padding: 0 10px;
  margin: 0 5px;
}

#window { padding: 0 10px; }

#cpu, #memory, #temperature, #network, #pulseaudio,
#battery, #clock, #custom-gpu, #idle_inhibitor, #mpd, #tray,
#custom-notification, #custom-power, #custom-fan, #custom-load,
#custom-power-profile, #custom-disk-space, #backlight, #bluetooth {
  padding: 0 10px;
  margin: 0 5px;
  color: #${palette.fg};
}

#cpu { background-color: #${palette.surface1}; }
#memory { background-color: #${palette.surface2}; }
#temperature { background-color: #${palette.muted}; }
#custom-fan { background-color: #${palette.surface1}; }
#custom-load { background-color: #${palette.surface2}; }
#custom-power-profile { background-color: #${palette.muted}; }
#custom-disk-space { background-color: #${palette.surface1}; }
#network { background-color: #${palette.surface2}; }
#bluetooth { background-color: #${palette.muted}; }
#pulseaudio { background-color: #${palette.surface1}; }
#battery { background-color: #${palette.surface2}; }
#backlight { background-color: #${palette.muted}; }
#clock { background-color: #${palette.surface1}; color: #${palette.fg}; }
#custom-gpu { background-color: #${palette.surface2}; }
#idle_inhibitor { background-color: #${palette.muted}; }
#mpd { background-color: #${palette.surface1}; }
#tray { background-color: #${palette.surface2}; }
#custom-notification { background-color: #${palette.muted}; }
#custom-power { background-color: #${palette.surface1}; }

/* Specific styles for custom modules based on their class */
.intel { color: #${palette.ansi.blue}; }
.nvidia { color: #${palette.ansi.green}; }
.performance { color: #${palette.ansi.red}; }
.disconnected { color: #${palette.crit}; }
.excellent { color: #${palette.good}; }
.good { color: #${palette.info}; }
.fair { color: #${palette.warn}; }
.poor { color: #${palette.crit}; }
.charging { color: #${palette.good}; }
.full { color: #${palette.good}; }
.high { color: #${palette.info}; }
.medium { color: #${palette.warn}; }
.low { color: #${palette.crit}; }
.critical { color: #${palette.crit}; }
.normal { color: #${palette.fg}; }
.idle { color: #${palette.ansi.cyan}; }
.warning { color: #${palette.warn}; }
.balanced { color: #${palette.info}; }
.powersave { color: #${palette.good}; }
.unknown { color: #${palette.muted}; }
''
