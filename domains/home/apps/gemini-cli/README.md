# gemini-cli

## Purpose
Installs Google's Gemini CLI (when `pkgs.gemini-cli` exists) and sources the `gemini-api-key` agenix secret into zsh so the key is available in interactive shells. Enable via `hwc.home.apps.gemini-cli.enable`.

## Boundaries
- ✅ Conditional package install and a zsh `initContent` block that sources the secret file when the host declares `age.secrets.gemini-api-key`.
- ❌ Does not declare the secret (`domains/secrets/declarations/`); no bash support (bash branch deliberately removed 2026-06-11); no Gemini config files.

## Structure
- `index.nix` — enable option, conditional package, secret-sourcing zsh init.

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
