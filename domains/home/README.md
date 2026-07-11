# Home Domain

## Purpose

Home Manager lane: user applications, dotfiles, theming, and personal
workflows. This domain is OS-agnostic by design — every module evaluates
with `osConfig = {}` (Law 1) so the same configuration runs under
HM-as-module (nixos-rebuild) and HM-as-flake (`hms`).

## Boundaries

- Manages: HM app modules (`hwc.home.apps.*`), the CLI core
  (`hwc.home.core.{shell,development}.*`), theming (`hwc.home.theme.*`).
- Does NOT manage: mail (top-level `domains/mail/`, namespace `hwc.mail.*`),
  system-lane services, machine membership (flake.nix machines table).
- System-lane halves live beside apps as `sys.nix`, gathered by
  `profiles/base/sys.nix` (Law 7) — they never reach the HM lane.

## Structure

```
domains/home/
├── apps/    # 50 app modules, auto-imported via readDir (index.nix per app,
│            # optional sys.nix system half, parts/ for split config)
├── core/    # shell/ (CLI env, zsh, aliases — parts/), development/, xdg-dirs.nix
└── theme/   # palettes/ (deep-nord, gruv, hwc), templates/gtk.nix, fonts/
```

One-package apps use `domains/lib/mkSimpleApp.nix`; cross-lane helpers
(`isNixOSHost`, `osCfgOr`, `sysLaneAssert`) live in `domains/lib/hm.nix`.

## Theme access (canonical)

Modules read theme tokens with the guarded form, never by importing
palette files directly:

```nix
colors = (config.hwc.home.theme or {}).colors or {};
uiFont = ((config.hwc.home.theme or {}).fonts or {}).ui or "Hack Nerd Font";
```

`hwc.home.theme.colors` is the materialized palette;
`hwc.home.theme.{cursor,icons,gtkTheme,typography}` carry look-and-feel
tokens consumed by `theme/templates/gtk.nix` and hyprland session parts.

## Changelog
- 2026-07-11: Law 3 migration — shell + scraper `nixosPath` standalone-HM fallback now derives from `config.home.homeDirectory` (gpu-screen-recorder escape-hatch precedent) instead of a `/home/eric` literal; hyprland session.nix stale commented-out screenshots fallback removed; yazi keymap.nix dead `? "/mnt/media"` default param dropped (index.nix always passes `mediaRoot`). Rendered values unchanged.

- 2026-07-06: shell: web-build alias repointed to /opt/business/website-site (website eviction).
- 2026-07-06: Browser migration: `apps/librewolf/` → `apps/firefox/` (librewolf unmaintained in nixpkgs, insecure-flagged). Same theme/launcher architecture; hardening prefs ported minus FPP +AllTargets; `firefox-hwc` replaces `librewolf-hwc` (hyprland keybind updated); insecure-package permit dropped from flake.nix.
- 2026-07-03: apps/waybar — lid-close default flipped to **suspend**: removed
  the `hwc-lid-state-init` user service that created `/run/user/$UID/hwc-lid-ignore`
  at login (which made lid close a no-op by default and was easy to mistake for
  armed). The state file now only exists when the waybar lid-toggle explicitly
  disables sleep; acpid handler semantics unchanged (absent = suspend).
- 2026-06-12: apps/qutebrowser fleshed out from empty scaffold — generated
  config.py with hwc-palette theming (parts/appearance.nix: tabs, statusbar,
  completion, hints, messages, downloads), Space-leader keybindings matching
  the yazi/todui grammar (parts/keybindings.nix: dd=tab-close, <Space>t tabs,
  <Space>y yank variants, <Space>m mpv handoff), nvim-in-kitty as editor,
  adblock (hosts + Brave lib), forced dark mode. Default browser unchanged
  (chromium owns the http/https handlers).
- 2026-06-12: apps/librewolf perf fix — drop `+AllTargets` from
  `privacy.fingerprintingProtection.overrides` (behavior.nix). +AllTargets is
  RFP-by-another-name: CanvasRandomization froze long-lived SPAs (claude.ai),
  timer fuzzing janked YouTube, frame-rate spoofing hurt WebGL. Now uses the
  default balanced FPP target set, keeping the `-CSSPrefersColorScheme` and
  `-WebGLRenderCapability` exclusions as explicit guarantees. Verified before
  the change: hwc profile live with user.js applied, nothing perf-relevant
  lockPref'd in mozilla.cfg, VA-API iHD decode working.
- 2026-06-12: apps/claude-code gains `shareConfig` — symlinks
  `~/.claude/{skills,agents,commands,CLAUDE.md}` from a standalone
  `~/.claude-config` git repo via `mkOutOfStoreSymlink` (single source of
  truth across hosts; branch-immune by living outside ~/.nixos). Decoupled
  from `enable`: hwc-server opts into `shareConfig.enable` only (npm-global
  claude, no Nix package / Obsidian cert). Optional `autoPull` systemd-user
  timer for zero-touch receive (default off). machines/server/home.nix opts in.
- 2026-06-12: Default browser laptop change librewolf → chromium. Moved the
  `xdg.mimeApps.defaultApplications` http(s)/html registration out of
  `apps/librewolf/index.nix` and into `apps/chromium/index.nix` (now points at
  `chromium-browser.desktop`) — the default-handler registration follows the
  default browser. LibreWolf's `librewolf-hwc` desktop-entry override stays so it
  still launches via SUPER+SHIFT+B; SUPER+B already launched chromium-hwc.
- 2026-06-11: Fix SUPER+E mail keybind: `ssh -t hwc aerc` referenced a
  nonexistent SSH host alias (only `server` exists), so the kitty window
  died instantly — now `ssh -t server aerc` (hyprland/parts/behavior.nix).
  core/shell `aliases` option semantics changed: default is now `{}` and
  definitions merge OVER the base set from parts/aliases.nix instead of
  replacing it (previously any per-machine alias definition would have
  silently clobbered all defaults). machines/laptop/home.nix uses this to
  alias `aerc` → `ssh -t server aerc` (laptop mbsync is disabled; mail
  lives on the server).
- 2026-06-11: Dormant-app cleanup (Eric's call on the fresh-eyes review
  §2.9): apps/thunderbird, apps/betterbird, apps/transcript-formatter
  deleted (never enabled anywhere). transcript-formatter's assets moved
  out of the repo to ~/apps/transcript-formatter (with a RUN.md); its
  workspace/media/youtube-services/transcript-formatter source dir is
  gone — only the DISABLED legacyApi referenced it at runtime (the live
  yt-transcripts-api v2 runs api.py from the parent dir, unaffected).
  apps/jellyfin-media-player KEPT — the review wrongly called it dormant;
  hwc-firestick enables it (autoStart) as its Jellyfin client.
- 2026-06-11: New apps/exodos/ — eXoDOS flatpak auto-install + exogui
  launcher, extracted from verbatim-identical blocks in
  machines/{laptop,kids}/home.nix. Collection path is the `root` option
  (defaults to ~/eXoDOS via home.homeDirectory — removes the hardcoded
  /home/eric literals).
- 2026-06-11: Structural cleanups — core/shell split into parts/ (aliases,
  ssh, zsh-init, prompt, fzf); 13 one-package app modules collapsed onto
  domains/lib/mkSimpleApp.nix; cross-lane boilerplate centralized in
  domains/lib/hm.nix (isNixOSHost/osCfgOr/sysLaneAssert, 7 modules);
  stale scaffolding removed (hyprland-new/-bak filters, 3 empty placeholder
  sys.nix, nvim .luarc.json, machines/laptop/home.bak, modules/home/
  headers, qutebrowser TODO).
- 2026-06-11: Law 2 namespace fix — hwc.home.shell.* -> hwc.home.core.shell.*
  and hwc.home.development.* -> hwc.home.core.development.* (namespace =
  folder, no exceptions). All setters/readers updated in one commit.
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
Options live under `hwc.home.apps.<name>.*`; defaults come from the role
home halves (`profiles/base/home.nix`, `profiles/desktop/home.nix`);
per-machine adjustments go in `machines/<host>/home.nix`. Current set
(52 modules):
```
aider, analysis, betterbird, blender, bottles-unwrapped, calcure,
calcurse, chromium, claude-code, claude-desktop, codex, dt, dxlog,
freecad, gemini-cli, google-cloud-sdk, gpg, herdr, hyprland, imv,
ipcalc, jellyfin-media-player, kitty, librewolf, localsend, markitdown,
mpv, n8n, neomutt, nvim, obsidian, onlyoffice-desktopeditors, opencode,
proton-authenticator, proton-mail, proton-pass, qbittorrent, qutebrowser,
scraper, slack, slack-cli, swaync, thunar, thunderbird, tmux, transcript-formatter,
tuxedo, wasistlos, waybar, whisper-cpp, xournalpp, yazi
```
Update this list whenever `domains/home/apps/` gains or loses a module.

### Workspace Support (`workspace/home/`)

```
workspace/home/
├── mail/                 # Mail support scripts
├── scraper/              # Social media scraper (referenced by apps/scraper/index.nix)
├── website_seo_scraper/  # SEO analysis tool
└── photo-dedup/          # Duplicate photo finder (referenced by shell alias)
```

## Usage
- Toggle modules via `hwc.home.*` options. Defaults live in the role home
  halves; machine one-offs in `machines/<host>/home.nix`.
- `domains/home/index.nix` reaches every machine through
  `profiles/base/home.nix`, which feeds **both** activation paths
  (HM-as-module and `hms`) from one source via the flake glue.
