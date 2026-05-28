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
- 2026-05-21: librewolf — session persistence (step 4/4 of connectivity refit). Stop sanitize-on-shutdown wiping cookies/cache/sessions, set cookie lifetime back to honoring the site's own headers (was forced session-only), restore previous session on startup, re-enable disk cache. Net: login survives browser close (claude.ai, JobTread, etc.) and pages don't refetch unchanged assets
- 2026-05-21: chromium — managed policy `RestoreOnStartup = 1` written to `/etc/chromium/policies/managed/hwc.json` via sys.nix. Chromium now restores the previous session on launch, which also preserves session-only cookies across browser restart (companion to the librewolf step 4 — same goal: stay signed into JobTread/etc.)
- 2026-05-21: librewolf — added `media.peerconnection.ice.no_host = false` override. Stray pref was sitting in prefs.js (toggled in a past session, not in our config or LibreWolf's mozilla.cfg) and silently blocked LAN-host ICE candidates, breaking local-network WebRTC scenarios. Public-internet Zoom/Meet were unaffected because they use STUN/TURN
- 2026-05-21: librewolf-hwc + chromium-hwc launchers — replaced `unset __EGL_VENDOR_LIBRARY_FILENAMES` with explicit `export __EGL_VENDOR_LIBRARY_FILENAMES=/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json`. Defense-in-depth match for the matching system-side pin in greetd's hyprStart. The previous `unset` was well-intentioned but fell back to libglvnd's default enumeration, where 10_nvidia.json (priority 10) outranks 50_mesa.json (priority 50) — `libEGL_nvidia.so` was getting loaded into both browsers' processes despite the Intel Wayland session, which broke WebGL context creation
- 2026-05-21: librewolf — `privacy.fingerprintingProtection.overrides` now excludes `WebGLRenderCapability` in addition to `CSSPrefersColorScheme`. The `+AllTargets` flag was silently including the WebGL-render FPP target, which blocks WebGL context creation at the content-process level even with `webgl.disabled=false`. Manifested as "WebGL supported but disabled or unavailable" on webglreport.com; Firefox unaffected (doesn't ship LibreWolf's FPP+webgl-render override). LibreWolf upstream issue: Codeberg #2381
- 2026-05-21: librewolf-hwc + chromium-hwc launchers — reverted EGL ICD pinning (back to `unset __EGL_VENDOR_LIBRARY_FILENAMES`). The pin was added to fix LibreWolf WebGL, but the real cause was the FPP `WebGLRenderCapability` target (see previous entry). Confirmed by testing with `nix-shell -p firefox` — Firefox using the same Intel-Mesa EGL stack worked fine. The EGL pin was unnecessary defense-in-depth against a misdiagnosed problem
- 2026-05-28: Added dxlog — DataX OpenSearch log diagnostic CLI (trace/search/errors/loops/live commands). Bash script wrapped via `writeShellScriptBin` from `parts/dxlog.sh`; runtime deps curl/jq/doctl pulled in via home.packages. Replaces ad-hoc copy at `~/000_inbox/downloads/dxlog.sh`
- 2026-05-28: dxlog — added interactive wizard (launches on `dxlog` with no args) walking action → identifier → time period → limit → format → output destination; auto-saves to `~/dxlog-reports/<slug>-<timestamp>.<ext>` by default. Also made `cmd_init` no-op when env vars are already populated (prevents the user from accidentally clobbering the Nix wrapper's exports by running `dxlog init`)
