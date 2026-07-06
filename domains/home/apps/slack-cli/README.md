# slack-cli

## Purpose
Installs the Slack terminal client, wrapped so its binary is exposed as
`slack-term` instead of `slack` — avoiding a PATH collision with the Slack
desktop client's binary.

## Boundaries
- ✅ Installs a symlinkJoin-wrapped `pkgs.slack-cli` when `hwc.home.apps.slack-cli.enable = true` (binary renamed `slack` → `slack-term`)
- ❌ No slack-cli configuration or auth tokens — set up interactively at runtime
- ❌ Not the desktop client — see `domains/home/apps/slack/`

## Structure
- `index.nix` — options + symlinkJoin/makeWrapper rename and package install

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
