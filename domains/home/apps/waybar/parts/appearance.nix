{ config, lib, pkgs, osConfig ? {}, ...}:
let
  theme = config.hwc.home.theme or {};
  colors = theme.colors or {};
  uiFont = (theme.fonts or {}).ui or "Hack Nerd Font";
in
''
/* HWC Waybar — colors supplied by hwc.home.theme.palette */

window#waybar {
  background-color: alpha(#${colors.bg1}, 0.88);
  color: #${colors.fg1};
  font-family: "${uiFont}";
  font-weight: bold;
  font-size: 16px;
  border-radius: 0px;
  margin: 0px 0px;
  padding: 5px 0px;
}

#workspaces {
  margin: 0;
  padding: 0;
  background-color: #${colors.sectionB};
}

#workspaces button {
  padding: 8px 12px;
  min-height: 0;
  min-width: 26px;
  background-color: #${colors.sectionB};
  color: #${colors.bg1};
  border-radius: 0;
  font-size: 16px;
  transition: none;
  border: none;
}

/* Empty: same section background, dimmed via opacity so powerline stays uniform */
#workspaces button.empty {
  background-color: #${colors.sectionB};
  color: #${colors.bg1};
  opacity: 0.4;
}

#workspaces button.active {
  background-color: #${colors.accent};
  color: #${colors.bg1};
  opacity: 1;
}

#workspaces button.urgent {
  background-color: #${colors.error};
  color: #${colors.bg1};
}

#workspaces button:hover {
  background-color: #${colors.accent2};
}

/* === MODE === */
#mode {
  background-color: #${colors.bg3};
  color: #${colors.fg1};
  border-radius: 0px;
  padding: 0px 8px;
  margin: 8px 4px;
}

/* === CLOCK & WEATHER — palette accent underline === */
#clock, #custom-weather, #custom-khal {
  padding: 8px 10px;
  min-height: 0;
  background-color: #${colors.bg3};
  color: #${colors.fg0};
  border: none;
  border-bottom: 2px solid #${colors.accent};
  border-radius: 0px;
  margin: 0px 0px;
  font-size: 16px;
  font-weight: 700;
  transition: all 0.2s ease;
}

/* === BASE MODULE STYLE === */
#cpu, #memory, #temperature, #custom-network, #pulseaudio,
#custom-battery, #custom-gpu, #custom-ollama, #custom-dt, #idle_inhibitor, #mpd, #tray,
#custom-notification, #custom-power, #custom-disk-space, #backlight, #bluetooth,
#custom-lid-sleep, #custom-proton-auth, #custom-recording, #hyprland-language {
  padding: 8px 6px;
  min-height: 0;
  margin: 0px 0px;
  background-color: #${colors.bg2};
  border: none;
  border-radius: 0px;
  color: #${colors.fg1};
  font-size: 16px;
  transition: all 0.2s ease;
}

/* === COLOR GROUPS — opaque palette sections, required for powerline seams === */
/* In gruv, sectionA-C are exact 50% accent blends over surface0; sectionD is bg3. */

/* Toggles */
#custom-gpu, #custom-ollama, #custom-dt, #idle_inhibitor, #custom-lid-sleep, #custom-recording {
  background-color: #${colors.sectionB};
}

/* recording status-classes (driven by `gsr-status` JSON `class` field) */
#custom-recording.recording { color: #${colors.error}; font-weight: bold; }
#custom-recording.off       { opacity: 0.55; }                      /* dimmed — idle */

/* dt status-classes (driven by `dt status --waybar` JSON `class` field) */
#custom-dt.active { color: #${colors.success}; font-weight: bold; }
#custom-dt.idle   { color: #${colors.fg1}; }
#custom-dt.stale  { color: #${colors.error}; font-weight: bold; }

/* Connectivity */
#pulseaudio, #bluetooth, #custom-network {
  background-color: #${colors.sectionC};
}

#custom-network { padding-right: 10px; }

/* System health */
#temperature, #custom-disk-space, #custom-battery {
  background-color: #${colors.sectionA};
}

/* Actions */
#custom-proton-auth, #tray, #custom-notification, #custom-power {
  background-color: #${colors.sectionD};
}

/* === POWERLINE SEPARATORS === */
/* Convention: color = left-section-bg, background-color = right-section-bg */
#custom-ws-enter, #custom-ws-exit,
#custom-sep-pre,
#custom-sep-1, #custom-sep-2, #custom-sep-3 {
  padding: 0;
  margin: 0;
  font-size: 18px;
  border: none;
  min-width: 0;
}

/* ws-enter: powerline entry arrow — translucent bar color on opaque workspace section */
#custom-ws-enter { color: alpha(#${colors.bg1}, 0.88); background-color: #${colors.sectionB}; }

/* Workspace link toggle — grouped visually with workspace section */
#custom-workspace-link {
  padding: 8px 10px;
  background-color: #${colors.sectionB};
  color: #${colors.bg1};
  font-size: 14px;
}
#custom-workspace-link.linked { color: #${colors.success}; }
#custom-workspace-link.split  { opacity: 0.55; }

#custom-sep-pre { color: #${colors.bg1}; background-color: #${colors.sectionB}; }  /* bar → toggle */
#custom-sep-1   { color: #${colors.sectionB}; background-color: #${colors.sectionC}; }  /* toggle → conn */
#custom-sep-2   { color: #${colors.sectionC}; background-color: #${colors.sectionA}; }  /* conn → health */
#custom-sep-3   { color: #${colors.sectionA}; background-color: #${colors.sectionD}; }  /* health → actions */

/* === HOVER — universal === */
#cpu:hover, #memory:hover, #temperature:hover, #custom-network:hover, #pulseaudio:hover,
#custom-battery:hover, #clock:hover, #custom-gpu:hover, #custom-ollama:hover, #custom-dt:hover,
#idle_inhibitor:hover, #mpd:hover, #tray:hover, #custom-notification:hover,
#custom-power:hover, #custom-disk-space:hover, #backlight:hover, #bluetooth:hover,
#custom-weather:hover, #custom-khal:hover, #custom-lid-sleep:hover, #custom-proton-auth:hover,
#custom-workspace-link:hover, #custom-recording:hover, #hyprland-language:hover {
  background-color: #${colors.bg3};
}

/* === STATE CLASSES (semantic — keep palette refs) === */

.stopped, .sleep-disabled {
  text-decoration: line-through;
  opacity: 0.6;
}

.intel        { color: #${colors.info}; }
.nvidia       { color: #${colors.success}; }
.performance  { color: #${colors.error}; }
.disconnected { color: #${colors.error}; text-decoration: line-through; opacity: 0.6; }
.excellent    { color: #${colors.success}; }
.good         { color: #${colors.successDim}; }
.fair         { color: #${colors.warning}; }
.poor         { color: #${colors.accent}; }
.charging     { color: #${colors.success}; }
.full         { color: #${colors.success}; }
.high         { color: #${colors.info}; }
.medium       { color: #${colors.warning}; }
.low          { color: #${colors.accent}; }
.critical     { color: #${colors.error}; }
.normal       { color: #${colors.fg1}; }
.idle         { color: #${colors.successDim}; }
.warning      { color: #${colors.warning}; }
.balanced     { color: #${colors.info}; }
.powersave    { color: #${colors.success}; }
.unknown      { color: #${colors.fg2}; }
.running      { color: #${colors.success}; }
.weather      { color: #${colors.fg1}; }
.sleep-enabled { color: #${colors.success}; }
''
