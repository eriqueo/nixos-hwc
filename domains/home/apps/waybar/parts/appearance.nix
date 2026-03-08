{ config, lib, pkgs, osConfig ? {}, ...}:
let
  # Use the active theme from central configuration
  palette = config.hwc.home.theme.colors;
in
''
/* Generated from ${palette.name} palette - Modern rounded glass rice (Gruvbox Material Dark) */
window#waybar {
  background-color: rgba(40, 40, 40, 0.85);  /* bg = #282828 @ ~85% opacity for glass */
  color: #${palette.fg};
  border-radius: 18px;
  margin: 8px 14px 0 14px;
  box-shadow: 0 4px 15px rgba(0, 0, 0, 0.3);  /* subtle depth shadow */
}

#workspaces button {
  padding: 2px 8px;
  background-color: transparent;
  color: #${palette.fg};
  border-radius: 9999px; /* pill shape */
  margin: 0 2px;
  min-width: 20px;
  transition: all 0.25s ease;
}

#workspaces button.active {
  color: #${palette.accent};
  background-color: rgba(125, 174, 163, 0.25);  /* accent = #7daea3 @ 25% */
  border-bottom: 2px solid #${palette.accent};
}

#workspaces button.urgent {
  color: #${palette.crit};
}

#workspaces button:hover {
  background-color: rgba(235, 219, 178, 0.1);  /* fg0 = #ebdbb2 subtle hover */
}

#mode {
  background-color: #${palette.accent};
  color: #${palette.bg};
  border-radius: 8px;
  padding: 2px 12px;
  margin: 0 5px;
}

#window { padding: 0 14px; font-weight: 500; }

/* All modules get soft rounding + subtle bg tints */
#cpu, #memory, #temperature, #network, #pulseaudio,
#battery, #clock, #custom-gpu, #custom-ollama, #idle_inhibitor, #mpd, #tray,
#custom-notification, #custom-power, #custom-disk-space, #backlight, #bluetooth,
#custom-weather, #hyprland-language {
  padding: 4px 12px;
  margin: 0 4px;
  border-radius: 12px;
  color: #${palette.fg};
}

/* Your original module background tints (adjusted for Gruvbox feel) */
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
#custom-ollama { background-color: #${palette.muted}; }
#idle_inhibitor { background-color: #${palette.muted}; }
#mpd { background-color: #${palette.surface1}; }
#tray { background-color: #${palette.surface2}; }
#custom-notification { background-color: #${palette.muted}; }
#custom-power { background-color: #${palette.surface1}; }
#custom-weather { background-color: #${palette.surface2}; }

/* Your original class colors (unchanged) */
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
.running { color: #${palette.good}; }
.stopped { color: #${palette.muted}; }
.weather { color: #${palette.info}; }
''
