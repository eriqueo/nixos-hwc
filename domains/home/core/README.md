# Home Core

## Purpose
Foundational Home Manager configuration shared across all apps: the CLI
environment and user directory layout.

## Boundaries
- Manages: shell/CLI env (`hwc.home.core.shell.*`), development toolchains
  (`hwc.home.core.development.*`), XDG user directories.
- Does NOT manage: app-specific config → `apps/`, theming → `theme/`.

## Structure
```
core/
├── index.nix          # Aggregator
├── shell/             # hwc.home.core.shell — zsh, aliases, fzf, starship,
│   ├── index.nix      #   git, ssh, MCP config (options + wiring)
│   └── parts/         #   aliases, ssh, zsh-init, prompt, fzf
├── development/       # hwc.home.core.development — language toolchains
├── repo-hooks/        # hwc.home.core.repoHooks — pins core.hooksPath to a
│                      #   repo-tracked hooks dir (.githooks) at activation
└── xdg-dirs.nix       # XDG user directory layout (000_inbox, 100_hwc, …)
```

## Changelog
- 2026-08-30: `core/shell/` — starship zsh init moved from HM's `enableZshIntegration` into `parts/zsh-init.nix` (`_hwc_starship_init`). `starship init zsh` bakes the first `starship` on PATH, which is `~/.nix-profile/bin/starship` after any `hms`; the next `nixos-rebuild switch` removes that profile entry and every open shell printed `no such file or directory: ~/.nix-profile/bin/starship` three times per prompt. Init now forces the lookup to `/etc/profiles/per-user/$USER/bin/starship`, which both activation lanes leave in place. `_hwc_reinit_prompt` reuses the same helper.
- 2026-08-06: repo-hooks — new module. Git hooks were hand-placed per host
  (laptop pointed hooksPath at its own .git/hooks; server had /dev/null);
  now ~/.nixos ships tracked .githooks/ (pre-commit = the nine charter-law
  flake checks; post-commit = auto-push) and every host's activation
  self-heals core.hooksPath to it, claude-code-wiring style (02b0895b).
  Enabled fleet-wide via profiles/base/home.nix.
- 2026-07-17: shell — extended the `hwc.home.core.shell.ssh.matchBlocks` DSL
  with an optional `proxyCommand` field (translated in both API branches of
  parts/ssh.nix) and declared the `lil-box` host (Elliott's DataX box, reached
  via `cloudflared access ssh`; `forwardAgent = false`). Enables plain
  `ssh lil-box` on both hosts.
- 2026-07-11: shell/parts/fzf.nix — renamed `fileWidgetCommand` →
  `fileWidget.command` and `historyWidgetOptions` → `historyWidget.options`
  (HM option renames); values unchanged, silences two eval warnings.
  Branched on `nixosApiVersion` (ssh.nix pattern) — the new names only
  exist on unstable; stable (HM 25.11) keeps the old names.
- 2026-06-26: shell/parts/ssh.nix — set `enableDefaultConfig = false` on the
  stable (HM 25.11) branch to silence the `programs.ssh` default-values
  deprecation; the `matchBlocks."*"` block already replicates HM's defaults.
- 2026-06-11: Structure section updated to reality (shell/ and development/
  are directories; namespaces moved under hwc.home.core.* per Law 2; the
  phantom options.nix/shell.nix flat files are gone).
