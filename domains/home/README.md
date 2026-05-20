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
├── mail/              # End-to-end mail stack (accounts, sync, delivery, search)
└── theme/             # Fonts, palettes, templates for UI theming
```

## Subdomains
- **apps/** – Toggle per-app modules via `hwc.home.apps.<name>.enable`. Some provide paired system-lane integrations under the same folder (`sys.nix`).
- **environment/** – User shell and helper scripts (`environment/shell`, `environment/parts`, `environment/scripts`). Options are under `hwc.home.environment.*`.
- **mail/** – Proton Bridge, mbsync/imap, SMTP, notmuch, address book (`hwc.home.mail.*`). Mail-specific docs live here for migrations and debugging.
- **theme/** – Palettes, font sets, and templated assets for consistent look-and-feel (`hwc.home.theme.*`).
- **core/** – Minimal plumbing for shared defaults (e.g., XDG directories) consumed by other home modules.

## Applications (current modules)
Options live under `hwc.home.apps.<name>.*`; enable from the HM profile. Current set (36 modules):
```
aerc, betterbird, blender, bottles-unwrapped, chromium, codex, freecad,
gemini-cli, google-cloud-sdk, gpg, hyprland, ipcalc, jellyfin-media-player,
kitty, librewolf, localsend, mpv, n8n, neomutt, obsidian,
onlyoffice-desktopeditors, opencode, proton-authenticator, proton-mail,
proton-pass, qbittorrent, qutebrowser, slack, slack-cli, swaync,
thunar, thunderbird, wasistlos, waybar, wayvnc, yazi
```
Update this list whenever `domains/home/apps/` gains a new module so the count stays accurate.

### Workspace Support (`workspace/home/`)

```
workspace/home/
├── scraper/              # Social media scraper (referenced by apps/scraper/index.nix)
├── website_seo_scraper/  # SEO analysis tool
├── mail/                 # Mailbot
│   └── mailbot/
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
