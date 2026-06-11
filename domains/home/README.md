# Home Domain

## Scope & Boundary
- Home Manager lane only: user applications, dotfiles, theming, and personal workflows.
- Namespaces follow folder paths per Charter Law 2 (`hwc.home.*`, `hwc.home.apps.<name>.*`).
- System lane helpers live beside some apps as `sys.nix`, imported only from system profiles.

## Layout
```
domains/home/
├── apps/              # Application modules (HM lane, optional sys.nix per app)
├── core/              # Cross-cutting home defaults (e.g., XDG dirs)
├── environment/       # Shell + shared scripts for the user environment
└── theme/             # Fonts, palettes, templates for UI theming
```

> The mail stack lives at the top level under `domains/mail/` (namespace `hwc.mail.*`).

## Subdomains
- **apps/** – Toggle per-app modules via `hwc.home.apps.<name>.enable`. Some provide paired system-lane integrations under the same folder (`sys.nix`).
- **environment/** – User shell and helper scripts (`environment/shell`, `environment/parts`, `environment/scripts`). Options are under `hwc.home.environment.*`.
- **theme/** – Palettes, font sets, and templated assets for consistent look-and-feel (`hwc.home.theme.*`).
- **core/** – Minimal plumbing for shared defaults (e.g., XDG directories) consumed by other home modules.

## Changelog

- 2026-06-11: HM correctness fixes — freecad seed config dry-run safe
  (writeText + run install); unguarded activation commands get the `run`
  prefix (xdg-dirs, tuxedo, dt); codex release-binary derivation moved to
  apps/codex/parts/package.nix (laptop one-off pins it; server stays on
  stock pkgs.codex); duplicate hwc.home.shell.tmux surface removed in
  favor of apps/tmux; dead bash secret-sourcing branches dropped (aider,
  gemini-cli); GPG_TTY exported per-shell from zsh; librewolf registered
  as default browser via xdg.mimeApps; invalid thunar mime globs removed;
  betterbird prefs.js hazard flagged with HWC-WARNING + dead guard deleted.
- 2026-06-11: Theme honesty pass — declare the formerly-phantom
  hwc.home.theme.{cursor,icons,gtkTheme,typography} options and wire the
  palette cursor block through (xcursor only; hyprcursor assets are gone —
  backlog); neomutt keys off theme.palette; waybar's unused parts/theme.nix
  deleted (CSS de-hardcode logged as backlog; palettes gain sectionA-D
  tokens for it); fzf/starship colors derive from theme.colors; calcure/
  calcurse comments de-Norded (they use terminal ANSI slots); guarded
  theme reads standardized (tmux, swaync, waybar, hyprland, librewolf,
  kitty); theme.fonts.{mono,ui} tokens added — swaync's never-installed
  JetBrainsMono replaced by the ui token; qt follows GTK dark.
- 2026-06-11: systemd.user.startServices = "sd-switch" now set fleet-wide
  in profiles/base/home.nix; removed the per-module stray copy
  (transcript-formatter) and the waybar restartWaybar activation hack.
- 2026-06-11: Law 3 paths — web-build alias (core/shell), WATCH_FOLDER
  (apps/transcript-formatter) and the yazi media keybinding now derive from
  hwc.paths.{nixos,media.root} via guarded osConfig reads with the previous
  literals as Law-1 fallbacks.
- 2026-06-11: Inline apps/tuxedo/options.nix into its index.nix under
  # OPTIONS (Law 10 regression from 82e3792b).
- 2026-06-11: Delete apps/aerc/ — dead duplicate of domains/mail/aerc/
  with a latent eval crash (unguarded read of an undeclared namespace at
  index.nix:46); enabled nowhere. Also removed the stale untracked
  domains/home/mail/ .bak tree and the "add mail here" comment in index.nix.
- 2026-06-11: Delete apps/n8n/parts/n8n-workflows/ — 82 MB / 824 tracked
  files of vendored third-party repo (plus untracked .venv/db artifacts),
  referenced by nothing (Law 13). apps/n8n/index.nix retained.
- 2026-06-09: Law 9/10 — `core/development.nix` → `core/development/index.nix`, `core/shell.nix` → `core/shell/index.nix` (pure relocation; the `aliases` shell alias retargeted to the new path).
- 2026-06-09: Law 3 finish — claude-code NODE_EXTRA_CA_CERTS derives from `config.home.homeDirectory` (HM-native). HM drv hash unchanged.
- 2026-06-09: Law 10 migration — inlined the 9 remaining separate `options.nix` files (aerc, betterbird, dt, herdr, nvim, obsidian, scraper, thunderbird, yazi) into their `index.nix` under `# OPTIONS` banners. Pure relocation; verified by laptop + standalone-HM eval.
- 2026-06-09: Removed `apps/.wayvnc-disabled/` (renamed-off duplicate of the live `apps/wayvnc/`, imported nowhere; flagged in audit `docs/audit/2026-06-09-server-audit.md` §2.1, recoverable from git history).
- 2026-06-03: added `apps/whisper-cpp/` — owns the `whisper-cpp` (CUDA) package and declaratively places GGML model weights into `~/models/whisper/`. Models are fetched via hash-pinned `fetchurl` from huggingface and symlinked via `home.file`; a known-hashes attrset (`medium.en`, `large-v3`) gates the `models` enum. Removed the duplicate `whisper-cpp` package from `core/shell.nix` — single source of truth now lives in the new module. Enabled on `machines/laptop/home.nix` with both models; the pre-existing imperative copies were pre-seeded into the store via `nix store add-file` so first activation does not re-download 4.5 GB.
- 2026-05-27: `apps/thunar/index.nix` — replaced `xdg.configFile` management of `xfce4/xfconf/xfce-perchannel-xml/thunar.xml` (a runtime state file Thunar/xfconfd rewrites on column resize / view changes) with a seed-once `home.activation` script. The static-file approach caused recurring `.hm-bak` clobber errors because HM saw runtime mutations and tried to back them up against an existing backup slot. New mechanism: XML lives in the nix store via `pkgs.writeText`; activation copies it to `~/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml` only if absent. After first activation HM never touches it, so column-width tweaks and any user changes persist. Defaults still apply on fresh installs.
- 2026-05-25: wired clipboard history in `apps/hyprland/` — added `wl-paste --watch cliphist store` to session autostart and `${mod},V` keybind invoking `cliphist list | wofi --dmenu | cliphist decode | wl-copy`. `cliphist` and `wl-clipboard` were already in `basePkgs`; only the watcher daemon and the picker keybind were missing.
- 2026-05-23: added `apps/herdr/` — herdr v0.6.2 terminal agent multiplexer ("tmux for AI agents"). Foundation-tier HM app (peer of `kitty`, `tmux`, `yazi`). Installed from upstream `herdr-linux-x86_64` release binary via fetchurl + autoPatchelfHook (mirrors `codex` pattern; avoids pulling Rust+zig source toolchain). Enabled by default on laptop via `profiles/home-session.nix` and explicitly on server via `machines/server/home.nix`.
- 2026-05-21: removed dead `options.nix` files inside `apps/`, `apps/<each>/`, `core/`, `theme/` and `theme/fonts/`. These were legacy "split" files from before options were inlined into the corresponding `index.nix`; nothing imported them. Also removed orphan `apps/hyprland/parts/system.nix`, `apps/obsidian/parts/theme.nix`, `apps/yazi/parts/{plugins,theme}.nix` (the consumer index.nix files reference these only in stale "Inline the former *.nix content here" comments). Verified via per-file `rg "options\.nix" <sibling-index.nix>` (zero real imports) and full eval (drv hashes unchanged).
- 2026-05-21: removed dead `mail/` subtree (abook, accounts, aerc, afew, bridge, mbsync, msmtp, notmuch, parts, `index.nix`/`options.nix`). The live mail stack lives at `domains/mail/` (namespace `hwc.mail.*`); `domains/home/index.nix` listed only `core/theme/apps` in `wantedDirs`, so the home/mail tree was never imported. Verified via `rg -ln 'domains/home/mail|\\./home/mail' -t nix .` (zero real imports — only stale path-header comments and docs) and full eval (drv hashes unchanged from post-revert baseline).

## Applications (current modules)
Options live under `hwc.home.apps.<name>.*`; enable from the HM profile. Current set (38 modules):
```
aerc, betterbird, blender, bottles-unwrapped, chromium, codex, freecad,
gemini-cli, google-cloud-sdk, gpg, herdr, hyprland, ipcalc,
jellyfin-media-player, kitty, librewolf, localsend, mpv, n8n, neomutt,
obsidian, onlyoffice-desktopeditors, opencode, proton-authenticator,
proton-mail, proton-pass, qbittorrent, qutebrowser, slack, slack-cli,
swaync, thunar, thunderbird, wasistlos, waybar, wayvnc, whisper-cpp, yazi
```
Update this list whenever `domains/home/apps/` gains a new module so the count stays accurate.

### Workspace Support (`workspace/home/`)

```
workspace/home/
├── scraper/              # Social media scraper (referenced by apps/scraper/index.nix)
├── website_seo_scraper/  # SEO analysis tool
└── photo-dedup/          # Duplicate photo finder (referenced by shell alias)
```

## Usage
- Toggle modules via `hwc.home.*` options. Defaults live in `profiles/home-session.nix`; per-machine adjustments go in `machines/<host>/home.nix`.
- `domains/home/index.nix` is imported by `profiles/home-session.nix`, which feeds **both** activation paths from one source.
- Keep system-lane imports (`sys.nix` files) in system profiles only; the home lane must stay evaluatable on non-NixOS hosts (`osConfig` guarded).
- Follow Charter Laws: no hardcoded paths (use `config.hwc.paths.*`), namespace fidelity, and guarded assertions for cross-lane references.

## Activation paths
Two ways to apply the same configuration:

| Path | Command | When to use |
|------|---------|-------------|
| HM-as-module | `sudo nixos-rebuild switch --flake .#hwc-<host>` | System or mixed changes; what runs on boot |
| HM-as-flake  | `home-manager switch --flake ~/.nixos#eric@$(hostname)` (alias `hms`) | HM-only changes (fast, ~5–10s, no sudo) |

Both paths import `profiles/home-session.nix` + `machines/<host>/home.nix`, so options can't drift between them. They do **not** share a HM profile generation, however — alternating runs can produce "existing file in the way" errors as each side tries to claim the same dotfiles. The module path sets `backupFileExtension = "backup"`; the standalone path does not.
