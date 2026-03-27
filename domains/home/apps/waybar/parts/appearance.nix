{ config, lib, pkgs, osConfig ? {}, ...}:
let
  # Use the active theme from central configuration
  palette = config.hwc.home.theme.colors;
in
''
/* HWC Waybar — compact text-based, color-grouped by function */
window#waybar {
  background-color: rgba(35, 40, 45, 0.60);
  color: #${palette.fg};
  font-family: "Hack Nerd Font";
  font-weight: bold;
  font-size: 14px;
  border-radius: 0px;
  margin: 4px 8px 0 8px;
  padding: 0px 4px;
}

/* === WORKSPACES === */
#workspaces button {
  padding: 0px 6px;
  min-height: 0;
  background-color: #${palette.info};
  color: #${palette.fg};
  border-radius: 4px;
  margin: 2px 2px;
  min-width: 0px;
  font-size: 13px;
  transition: all 0.2s ease;
}

#workspaces button.empty {
  color: #${palette.fg};
  opacity: 0.5;
}

#workspaces button.active {
  color: #${palette.bg};
  background-color: #${palette.muted};
  opacity: 1;
}

#workspaces button.urgent {
  color: #${palette.crit};
  opacity: 1;
}

#workspaces button:hover {
  background-color: #${palette.bg0};
}

/* === MODE === */
#mode {
  background-color: #${palette.muted};
  color: #${palette.bg};
  border-radius: 4px;
  padding: 0px 8px;
  margin: 2px 4px;
}

/* === WINDOW TITLE === */
#window {
  padding: 0px 10px;
  font-weight: 500;
  min-height: 0;
  background-color: transparent;
  color: #${palette.good};
  border: 1px solid #${palette.muted};
  border-radius: 4px;
  margin: 2px 3px;
  transition: all 0.2s ease;
}

/* === BASE MODULE STYLE === */
#cpu, #memory, #temperature, #custom-network, #pulseaudio,
#custom-battery, #clock, #custom-gpu, #custom-ollama, #idle_inhibitor, #mpd, #tray,
#custom-notification, #custom-power, #custom-disk-space, #backlight, #bluetooth,
#custom-weather, #custom-lid-sleep, #custom-proton-auth, #hyprland-language {
  padding: 0px 6px;
  min-height: 0;
  margin: 2px 2px;
  background-color: transparent;
  border: 1px solid #${palette.muted};
  border-radius: 4px;
  color: #${palette.fg};
  font-size: 13px;
  transition: all 0.2s ease;
}

/* === COLOR GROUPS === */

/* Toggles — blue-grey tint (GPU, Ollama, Idle inhibitor, Lid sleep) */
#custom-gpu, #custom-ollama, #idle_inhibitor, #custom-lid-sleep {
  border-color: #${palette.ansi.blue};
  background-color: rgba(69, 133, 136, 0.15);
}

/* Connectivity — green tint (Audio, Bluetooth, Network) */
#pulseaudio, #bluetooth, #custom-network {
  border-color: #${palette.ansi.cyan};
  background-color: rgba(104, 157, 106, 0.15);
}

/* System health — copper tint (Temp, Disk, Battery) */
#temperature, #custom-disk-space, #custom-battery {
  border-color: #${palette.accent};
  background-color: rgba(207, 153, 95, 0.15);
}

/* Info — neutral (Clock, Weather, MPD) */
#clock, #custom-weather, #mpd {
  border-color: #${palette.fg2};
  background-color: rgba(167, 170, 173, 0.1);
}

/* Actions — subtle (Proton, Tray, Notify, Power) */
#custom-proton-auth, #tray, #custom-notification, #custom-power {
  border-color: #${palette.muted};
  background-color: transparent;
}

/* === HOVER — universal === */
#cpu:hover, #memory:hover, #temperature:hover, #custom-network:hover, #pulseaudio:hover,
#custom-battery:hover, #clock:hover, #custom-gpu:hover, #custom-ollama:hover,
#idle_inhibitor:hover, #mpd:hover, #tray:hover, #custom-notification:hover,
#custom-power:hover, #custom-disk-space:hover, #backlight:hover, #bluetooth:hover,
#custom-weather:hover, #custom-lid-sleep:hover, #custom-proton-auth:hover,
#hyprland-language:hover {
  background-color: rgba(213, 196, 161, 0.25);
}

/* === STATE CLASSES === */

/* Disabled/stopped — line-through + dimmed */
.stopped, .sleep-disabled {
  text-decoration: line-through;
  opacity: 0.6;
}

.intel { color: #${palette.ansi.blue}; }
.nvidia { color: #${palette.ansi.green}; }
.performance { color: #${palette.ansi.red}; }
.disconnected { color: #${palette.crit}; text-decoration: line-through; opacity: 0.6; }
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
.weather { color: #${palette.info}; }
.sleep-enabled { color: #${palette.good}; }
''
