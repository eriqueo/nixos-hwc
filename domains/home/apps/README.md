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
- 2026-04-22: Added markitdown file-to-Markdown converter (PDF, DOCX, XLSX, images, audio)
- 2026-05-21: librewolf — added `librewolf-hwc` GPU launcher wrapper (mirrors chromium-hwc: strips NVIDIA PRIME env, pins VA-API to iHD on Intel iGPU) — step 1/4 of connectivity refit
- 2026-05-21: librewolf — re-enabled WebGL, WebRTC (with ICE leak controls), EME/Widevine DRM, and clipboard events; overrides LibreWolf's librewolf.cfg hardening defaults that break Zoom/Meet/Maps/streaming — step 2/4 of connectivity refit
- 2026-05-21: librewolf + hyprland — desktop entry now routes through `librewolf-hwc` (wofi/rofi pick this up via user-dir XDG priority); hyprland SUPER+SHIFT+B keybind switched from `gpu-launch librewolf` to `gpu-launch librewolf-hwc` so GPU-isolation wrapper is always in the path — step 3/4 of connectivity refit (swapped ahead of session-persistence step on request)
