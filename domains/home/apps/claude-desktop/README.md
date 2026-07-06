# claude-desktop

## Purpose
Installs the Claude Desktop GUI — the Cowork-capable Linux port (`pkgs.claude-cowork-linux`, from the `claude-cowork` flake input / overlay, source github:johnzfitch/claude-cowork-linux). Runs Claude Code under bubblewrap with bundled runtime deps. Enable via `hwc.home.apps.claude-desktop.enable`.

## Boundaries
- ✅ The package in `home.packages` — nothing else.
- ❌ Does not manage MCP config (`~/.config/Claude/claude_desktop_config.json` is deliberately untouched); the flake input/overlay lives in `flake.nix`, not here; keyring backend comes from the gpg module's pass-secret-service.

## Structure
- `index.nix` — enable option and package install.

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
