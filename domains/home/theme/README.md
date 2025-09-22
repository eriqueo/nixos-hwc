# Meta-Summary: How Domains Interconnect
## Core Idea -
**Single Source of Truth**:
      - All colors and theme tokens come from palettes/ (e.g. deep-nord.nix). -
**Adapters**: 
      - Translate palette → per-app or per-system config format (GTK, Waybar CSS, Hyprland, etc). - 
**Apps**: 
      - Import adapters (or palette directly if no adapter exists).  
**System Tools**: 
      - For Hyprland and Waybar, provide helper scripts that integrate with system services. - 
**Profiles**: 
      - User selects imports in profiles/workstation.nix → toggles which apps/tools are active. --- 
**Flow of Control**  
### 1. Palette → Adapters  
      - Palettes live in domains/home/theme/palettes/.  
      - Each adapter (gtk.nix, waybar-css.nix, hyprland.nix) pulls tokens from the palette. - 
      - Output = config snippets (GTK configs, CSS variables, Hyprland options). 
### 2. Adapters → Applications 
      - Apps like **Thunar**: import GTK adapter for theming. 
      - Apps like **Kitty**: import palette directly and map tokens → color0–15. 
      - Browsers (Firefox/Chromium/LibreWolf): need dedicated adapters (CSS/userChrome injection). 
      - Betterbird: planned to use Thunderbird module + custom CSS adapter. 
### 3. Home Manager vs System Integration - 
**Home Manager scope**: 
      - Programs configured per-user (programs.kitty, programs.waybar). 
      - XDG configs like ~/.config/gtk-3.0/gtk.css or ~/.config/waybar/style.css. 
**System scope**: 
      - Packages and scripts exposed via environment.systemPackages. 
      - Examples: Waybar GPU scripts, Hyprland monitor toggle. 
      - Convention: both live inside the same app folder (apps/waybar/, hyprland/parts/), split into default.nix (home) and system.nix. 
### 4. Profiles (Entry Point) 
      - profiles/workstation.nix imports all relevant modules: 
      - domains/home/apps/kitty.nix 
      - domains/home/apps/thunar.nix 
      - domains/home/apps/waybar/default.nix 
      - domains/home/hyprland/default.nix 
      - Profiles decide which domains are active for a given machine. --- 
## Theming Workflow 
      1. User sets palette in domains/home/theme/palettes/. 
        - Future: config.hwc.home.theme.palette = "deep-nord"; 
      2. Adapters translate into system-specific formats. 
      3. Apps read from adapters (or palette directly). 
      4. To **switch theme**: 
        - Change palette import (or palette option). 
        - Rebuild system (nixos-rebuild switch). 
        - All apps update together.
## Goal State - **1 Palette → Many Adapters → All Apps**. 
      - One edit (palette hex values) changes entire system look. 
      - Apps grouped logically, each folder contains everything (Home Manager + system tools).
