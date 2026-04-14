# Home Apps

## Purpose
User application configuration via Home Manager.

## Boundaries
- Manages: App configs, dotfiles, user packages, desktop entries
- Does NOT manage: System deps → `system/apps/` (via sys.nix), services → `server/`

## Structure
```
apps/
├── aerc/           # Email client
├── aider/          # AI coding assistant
├── blender/        # 3D modeling
├── chromium/       # Browser
├── freecad/        # CAD software
├── hyprland/       # Wayland compositor
├── kitty/          # Terminal emulator
├── librewolf/      # Privacy browser
├── mpv/            # Media player
├── obsidian/       # Note-taking
├── waybar/         # Status bar
└── ... (30+ apps)
```

## Changelog
- 2026-02-28: Added README for Charter Law 12 compliance
- 2026-03-14: Added calcurse and calcure TUI calendar apps with Nord theme
- 2026-03-15: Added tmux terminal multiplexer with vi keys, C-a prefix, Gruvbox status bar
