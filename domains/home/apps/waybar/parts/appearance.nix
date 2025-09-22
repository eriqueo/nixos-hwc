{ config, lib, pkgs, theme, ... }:
let
  # Import the palette directly to get color values
  palette = import ../../../theme/palettes/deep-nord.nix {};
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

#cpu, #memory, #temperature,  #network, #pulseaudio,
#battery, #clock, #custom-gpu, #idle_inhibitor, #mpd, #tray,
#custom-notification, #custom-power {
  padding: 0 10px;
  margin: 0 5px;
  color: #${palette.fg};
}

#cpu { background-color: #${palette.surface1}; }
#memory { background-color: #${palette.surface2}; }
#temperature { background-color: #${palette.muted}; }
#network { background-color: #${palette.surface2}; }
#pulseaudio { background-color: #${palette.muted}; }
#battery { background-color: #${palette.surface1}; }
#clock { background-color: #${palette.surface2}; color: #${palette.fg}; }
#custom-gpu { background-color: #${palette.muted}; }
#idle_inhibitor { background-color: #${palette.surface1}; }
#mpd { background-color: #${palette.surface2}; }
#tray { background-color: #${palette.muted}; }
#custom-notification { background-color: #${palette.surface1}; }
#custom-power { background-color: #${palette.surface2}; }

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
''
