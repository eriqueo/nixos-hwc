{ config, lib, pkgs, osConfig ? {}, ...}:
let
  # Use the active theme from central configuration
  palette = config.hwc.home.theme.colors;
in
''
/* HWC Waybar — Gruvbox Material Dark (official hex values) */

/* Gruvbox Material Dark palette reference:
   bg0=#32302f  bg1=#3c3836  bg3=#504945  bg5=#665c54
   fg0=#d4be98  fg1=#ddc7a1  grey0=#7c6f64  grey1=#928374
   blue=#7daea3  aqua=#89b482  green=#a9b665
   yellow=#d8a657  orange=#e78a4e  red=#ea6962  purple=#d3869b
*/

window#waybar {
  background-color: rgba(50, 48, 47, 0.88);  /* bg0 @ 88% */
  color: #d4be98;                             /* fg0 */
  font-family: "Hack Nerd Font";
  font-weight: bold;
  font-size: 18px;
  border-radius: 0px;
  margin: 0px 0px;
  padding: 12px 0px;
}

#workspaces {
  margin: 0;
  padding: 0;
  background-color: #576f69;
}

#workspaces button {
  padding: 12px 16px;
  min-height: 0;
  min-width: 32px;
  background-color: #576f69;
  color: #32302f;
  border-radius: 0;
  font-size: 18px;
  transition: none;
  border: none;
}

#workspaces button.empty {
  background-color: #3c3836;
  color: #7c6f64;
}

#workspaces button.active {
  background-color: #7daea3;
  color: #32302f;
}

#workspaces button.urgent {
  background-color: #ea6962;
  color: #32302f;
}

#workspaces button:hover {
  background-color: #6b8a84;
}

/* === MODE === */
#mode {
  background-color: #665c54;   /* bg5 */
  color: #d4be98;
  border-radius: 0px;
  padding: 0px 8px;
  margin: 8px 4px;
}

/* === CLOCK & WEATHER — cohesive with active workspace === */
#clock, #custom-weather {
  padding: 12px 10px;
  min-height: 0;
  background-color: #504945;   /* bg3 — same as active workspace */
  color: #ddc7a1;               /* fg1 */
  border: none;
  border-bottom: 2px solid #7daea3;  /* blue — same as active workspace */
  border-radius: 0px;
  margin: 0px 0px;
  font-size: 18px;
  font-weight: 700;
  transition: all 0.2s ease;
}

/* === BASE MODULE STYLE === */
#cpu, #memory, #temperature, #custom-network, #pulseaudio,
#custom-battery, #custom-gpu, #custom-ollama, #idle_inhibitor, #mpd, #tray,
#custom-notification, #custom-power, #custom-disk-space, #backlight, #bluetooth,
#custom-lid-sleep, #custom-proton-auth, #hyprland-language {
  padding: 12px 6px;
  min-height: 0;
  margin: 0px 0px;
  background-color: #3c3836;   /* bg1 baseline */
  border: none;
  border-radius: 0px;
  color: #d4be98;               /* fg0 */
  font-size: 18px;
  transition: all 0.2s ease;
}

/* === COLOR GROUPS — opaque computed (50% blend over #32302f, required for powerline) === */

/* Toggles — teal #576f69 */
#custom-gpu, #custom-ollama, #idle_inhibitor, #custom-lid-sleep {
  background-color: #576f69;
}

/* Connectivity — sage green #5d7258 */
#pulseaudio, #bluetooth, #custom-network {
  background-color: #5d7258;
}

#custom-network { padding-right: 10px; }

/* System health — amber #856b43 */
#temperature, #custom-disk-space, #custom-battery {
  background-color: #856b43;
}

/* Actions — bg3 #504945 */
#custom-proton-auth, #tray, #custom-notification, #custom-power {
  background-color: #504945;
}

/* === POWERLINE SEPARATORS === */
/* Convention: color = left-section-bg, background-color = right-section-bg */
/* The filled triangle points right; FG=left-color sits against BG=right-color */
#custom-ws-enter, #custom-ws-exit,
#custom-sep-pre,
#custom-sep-1, #custom-sep-2, #custom-sep-3 {
  padding: 0;
  margin: 0;
  font-size: 48px;
  border: none;
  min-width: 0;
}

/* Workspace entry: dark bar → teal block; exit: teal block → dark bar */
#custom-ws-enter { color: #32302f; background-color: #576f69; }  /* dark → teal */
#custom-ws-exit  { color: #576f69; background-color: #32302f; }  /* teal → dark */

#custom-sep-pre { color: #32302f; background-color: #576f69; }  /* bar → toggle */
#custom-sep-1   { color: #576f69; background-color: #5d7258; }  /* toggle → conn */
#custom-sep-2   { color: #5d7258; background-color: #856b43; }  /* conn → health */
#custom-sep-3   { color: #856b43; background-color: #504945; }  /* health → actions */

/* === HOVER — universal === */
#cpu:hover, #memory:hover, #temperature:hover, #custom-network:hover, #pulseaudio:hover,
#custom-battery:hover, #clock:hover, #custom-gpu:hover, #custom-ollama:hover,
#idle_inhibitor:hover, #mpd:hover, #tray:hover, #custom-notification:hover,
#custom-power:hover, #custom-disk-space:hover, #backlight:hover, #bluetooth:hover,
#custom-weather:hover, #custom-lid-sleep:hover, #custom-proton-auth:hover,
#hyprland-language:hover {
  background-color: #504945;   /* bg3 */
}

/* === STATE CLASSES (semantic — keep palette refs) === */

.stopped, .sleep-disabled {
  text-decoration: line-through;
  opacity: 0.6;
}

.intel        { color: #7daea3; }   /* blue */
.nvidia       { color: #a9b665; }   /* green */
.performance  { color: #ea6962; }   /* red */
.disconnected { color: #ea6962; text-decoration: line-through; opacity: 0.6; }
.excellent    { color: #a9b665; }
.good         { color: #89b482; }
.fair         { color: #d8a657; }
.poor         { color: #e78a4e; }
.charging     { color: #a9b665; }
.full         { color: #a9b665; }
.high         { color: #7daea3; }
.medium       { color: #d8a657; }
.low          { color: #e78a4e; }
.critical     { color: #ea6962; }
.normal       { color: #d4be98; }
.idle         { color: #89b482; }
.warning      { color: #d8a657; }
.balanced     { color: #7daea3; }
.powersave    { color: #a9b665; }
.unknown      { color: #7c6f64; }
.running      { color: #a9b665; }
.weather      { color: #d4be98; }
.sleep-enabled { color: #a9b665; }
''
