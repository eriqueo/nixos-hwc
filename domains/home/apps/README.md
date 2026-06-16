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
├── gpu-screen-recorder/  # Call/screen recording (gsr-toggle script + sys.nix capture wrapper)
├── hyprland/       # Wayland compositor
├── kitty/          # Terminal emulator
├── librewolf/      # Privacy browser
├── mpv/            # Media player
├── obsidian/       # Note-taking
├── xournalpp/      # PDF annotator / handwritten notes
├── waybar/         # Status bar
├── tuxedo/         # todo.txt TUI (keyboard-driven task manager)
├── todui/          # VTODO task TUI (external flake input; HWC adapter only)
└── ... (30+ apps)
```

## Changelog
- 2026-06-16: Law-12 sweep also refreshed `khalt/`, `nvim/`, and `todui/`
  sub-READMEs.
- 2026-06-16: workbench + keymap rollout — `a7a1a5e0` workbench TUI host
  with zellij + todui/khalt peers; `6d0f2eb4` usable layout (auto-start
  peers, tab/status bars, khalt month); `fc8ef8af` SUPER+W binding +
  `workbench` shell alias; `93bfcdef`/`cd328ee5` auto-start tuning
  (yazi/aerc/nvim, aerc lazy peer); `4c049cc1` home-page tab layout (host
  alone, tools as peer tabs); `2923a331` late-bind aerc to server +
  gateway → tailnet; `6ea8aeae` default to HWC hub; `60947776` reliable
  meta leader + host navigates to tabs (no dup panes). `4a801db6` unified
  keymap factory across apps; `64168d18` SUPER+SHIFT+I refinery-intake
  keybind; `7a3c91a2` khalt renders Radicale calendar + iCloud→Radicale
  migration.
- 2026-06-14: **khalt — full event CRUD in month/quarter modes**. The grid modes now embed the *same* event column as agenda in an `outermost` NPile, so `tab`/`shift tab` move focus between grid and list; with the list focused every khal command works identically (view/edit/delete/duplicate/export/external-edit). `n` creates on the grid's selected day; `enter` hands off focus. Mutations refresh the grid cells live via a new `ClassicView.on_events_changed()` hook wired into `EventColumn.update()`/`refresh_titles()`. Removes the prior "CRUD only in agenda" limitation. Verified live (tmux): new-from-grid writes an .ics and the cell updates; quarter behaves identically; clean exit.
- 2026-06-14: **khalt feature-complete + enabled** in `profiles/desktop`. Implemented the three upstream-impossible features in the fork (`~/600_apps/khalt`): (1) zoomable views — agenda ⇄ month grid ⇄ quarter (3-mo), `z` cycles, `space→v` switches (`khal/ui/khalt_grid.py`); (2) space-leader which-key menu w/ sub-menus, todui-style (`khalt_leader.py`); (3) palette inheritance — flat theme tokens → every ikhal/leader/grid role (`khalt_theme.py`). Translator now generates khalt's config from scratch (reusing the shared `hwc.mail.calendar` *data*) and injects `[palette_tokens]` from `hwc.home.theme.colors`, so the system theme genuinely drives khalt's colours (no hardcoded `[palette]`). HM module exposes a **bin-only** `khalt` wrapper (full package would collide with system `khal`'s python module in buildEnv). Verified: nix build + headless widget smoke test + tmux-driven live TUI. Options: `hwc.home.apps.khalt.{enable,defaultView,extraConfig}`.
- 2026-06-14: Added **khalt** scaffold — forked khal/ikhal (own repo `~/600_apps/khalt`, consumed as the `khalt` flake input), thin translator `domains/home/apps/khalt/` (namespace `hwc.home.apps.khalt`). Source fork of khal v0.14.0. Isolates via `~/.config/khalt/config` (`ikhal -c`). See `~/600_apps/khalt/README.hwc.md`.
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
- 2026-05-29: Added xournalpp — PDF annotator / handwritten notes. Use case: signing PDFs (draw signature or drop in a PNG image of one, export back to PDF preserving the original)
- 2026-06-09: Added tuxedo — keyboard-driven todo.txt TUI (webstonehq/tuxedo). Namespace `hwc.home.apps.tuxedo`; sets TODO_DIR/TODO_FILE/DONE_FILE env (default `~/000_inbox/todo`); seeds a writable config.toml via home.activation (tuxedo self-manages the file at runtime, so it is intentionally NOT an xdg.configFile store symlink). Package overridable via `.package` in case the nixpkgs attr differs from `tuxedo`
- 2026-06-11: Added gpu-screen-recorder — call/screen recording for Zoom/Meet. HM half (`hwc.home.apps.gpu-screen-recorder`) ships only the `gsr-toggle` start/stop script (focused monitor, merged call-audio+mic via `-a "default_output|default_input"`, saves to `$HWC_RECORDINGS_DIR`); the binary itself comes from the co-located sys.nix (`hwc.system.apps.gpu-screen-recorder` → nixpkgs `programs.gpu-screen-recorder`) because the setcap `gsr-kms-server` wrapperDir override only exists on the system lane — an HM-installed copy would shadow it and break promptless Wayland capture. Hyprland behavior.nix adds SHIFT+PRINT → `gsr-toggle` (dt-bind precedent). Enabled on hwc-laptop (both lanes)
- 2026-06-12: gpu-screen-recorder + waybar — fix waybar-suicide + cgroup-kill bugs found via journal (`status=43/RTMIN+9`, restart counter 5). (1) Recording now runs as its own transient user unit `gsr-record.service` via `systemd-run --user --collect` — click-started recordings no longer live in waybar's cgroup (they were SIGKILLed unfinalized on every waybar restart), and `systemctl is-active` replaces `pgrep -f` state detection (which false-matched any cmdline containing the pattern). (2) Waybar refresh signals now target the binary only: `pkill -RTMIN+N -x '\.waybar-wrapped|waybar'` — the bare form also hit `waybar-launch`, the bash wrapper that is waybar.service's MainPID; bash dies on unhandled RT signals → systemd fails the service → cgroup SIGKILL + restart. Same latent bug fixed in workspace-link's RTMIN+8 (it had been restarting waybar on every link toggle). Prior art: system/gpu/index.nix once removed a `pkill -SIGUSR1` for "waybar crashes" — same class, now root-caused
- 2026-06-11: gpu-screen-recorder + waybar — `custom/recording` widget in the teal toggles group (next to lid-sleep): shows "Rec", dimmed when idle, red+bold while recording, tooltip names the SHIFT+PRINT keybind, click runs `gsr-toggle`. New `gsr-status` script emits the waybar JSON; `gsr-toggle` now signals RTMIN+9 for instant refresh (RTMIN+8 was taken by workspace-link), with a 5s poll fallback in case the recorder dies without a toggle
- 2026-06-11: Added tasq — VTODO-native keyboard task TUI (Textual) over the Phase A Reminders sync vdir (`domains/mail/tasks/`). Namespace `hwc.home.apps.tasq`; python env packages todoman as a library via `toPythonModule pkgs.todoman` (no `python3Packages.todoman` exists); runner execs git-tracked source at `workspace/home/tasq/` live (scraper precedent — .py edits need no rebuild); own sqlite cache at `~/.cache/tasq/` separate from todoman CLI's. Enabled for the desktop role
- 2026-06-12: Retired in-tree `tasq` → external **`todui`**. tasq was rewritten as a standalone, todoman-free project (own repo `~/600_apps/todui`, own VTODO engine on icalendar, own tests/packaging/flake) and is now consumed as the `todui` flake input. `domains/home/apps/tasq/` + `workspace/home/tasq/` deleted; replaced by the thin translator `domains/home/apps/todui/` (namespace `hwc.home.apps.todui`) that feeds todui the system theme palette + Radicale creds. Input is a live-dev `path:` for now (pin to a git rev before hwc-server). See `todui/README.md`.
- 2026-06-13: claude-desktop — switched the Linux port from aaddrick/claude-desktop-debian to **johnzfitch/claude-cowork-linux** to get working Cowork (Local Agent Mode). aaddrick wraps the Debian Electron build in `buildFHSEnv`; inside that sandbox Electron's main-process networking was dead (13.7k `net::ERR_FAILED` on OAuth/sessions-bridge), so chat worked (renderer's own Chromium stack) but Cowork's main-process OAuth could never start a session. A version pin to rev `4a1bbc9e` was a misdiagnosis and didn't help. The new port extracts the macOS app, stubs the macOS-native modules (`@ant/claude-swift`, `@ant/claude-native`) in JS, translates VM `/sessions` paths to host paths in-process (no root symlink needed), and runs Claude Code directly under bubblewrap (no VM, no FHS wrapper) against nixpkgs `electron_41`. flake input renamed `claude-desktop` → `claude-cowork` (package-only flake exposed as `pkgs.claude-cowork-linux` via inline overlay in flake.nix); module now installs `pkgs.claude-cowork-linux`. Package bundles its own runtime deps (electron_41, bubblewrap, curl, zstd, dbus, …) on PATH; MCP config at `~/.config/Claude/claude_desktop_config.json` untouched. Laptop-only (server never imported the overlay).
- 2026-06-13: gpg — added opt-in `hwc.home.apps.gpg.secretService.enable` (off by default) that turns on `services.pass-secret-service`, bridging the existing `pass` store to the `org.freedesktop.secrets` D-Bus API. Enabled on hwc-laptop so Electron/libsecret apps (Claude Desktop OAuth tokens, Chromium, etc.) store secrets GPG-encrypted in `pass` instead of the weak `--password-store=basic` (laptop root `/` is unencrypted, so basic = tokens ~plaintext on disk). gpg-agent (already in the module — gnome3 pinentry, 2h cache) supplies the unlock path; Claude Desktop's launcher auto-detects the SecretService and upgrades off basic with no change to the claude-desktop module. Headless server stays off (no D-Bus session).
