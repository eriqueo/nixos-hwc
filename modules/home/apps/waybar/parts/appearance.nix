{ config, lib, pkgs, ... }:


# Ensure a newline separates the generated variables from the main styles.
''
  ${theme}

  /* Main Waybar styles follow */
  window#waybar {
    background-color: var(--background);
    color: var(--foreground);
  }

  #workspaces button {
    padding: 0 5px;
    background-color: transparent;
    color: var(--foreground);
    border-bottom: 2px solid transparent;
  }
  #workspaces button.active {
    color: var(--accent);
    border-bottom: 2px solid var(--accent);
  }
  #workspaces button.urgent {
    color: var(--crit);
    border-bottom: 2px solid var(--crit);
  }

  #mode {
    background-color: var(--accent);
    color: var(--background);
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
    color: var(--foreground);
  }

  #cpu { background-color: var(--color14); }
  #memory { background-color: var(--color13); }
  #temperature { background-color: var(--color12); }
  #disk { background-color: var(--color11); }
  #network { background-color: var(--color10); }
  #pulseaudio { background-color: var(--color9); }
  #battery { background-color: var(--color8); }
  #clock { background-color: var(--color7); }
  #custom-gpu { background-color: var(--color6); }
  #idle_inhibitor { background-color: var(--color5); }
  #mpd { background-color: var(--color4); }
  #tray { background-color: var(--color3); }
  #custom-notification { background-color: var(--color2); }
  #custom-power { background-color: var(--color1); }

  /* Specific styles for custom modules based on their class */
  .intel { color: var(--color4); }
  .nvidia { color: var(--color2); }
  .performance { color: var(--color1); }
  .disconnected { color: var(--error); }
  .excellent { color: var(--success); }
  .good { color: var(--info); }
  .fair { color: var(--warning); }
  .poor { color: var(--error); }
  .charging { color: var(--success); }
  .full { color: var(--success); }
  .high { color: var(--info); }
  .medium { color: var(--warning); }
  .low { color: var(--error); }
  .critical { color: var(--error); }
''
