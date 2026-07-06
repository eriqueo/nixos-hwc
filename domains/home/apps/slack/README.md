# slack

## Purpose
Installs the Slack desktop client. A one-package module generated via
`domains/lib/mkSimpleApp.nix` — no configuration is managed here.

## Boundaries
- ✅ Installs `pkgs.slack` when `hwc.home.apps.slack.enable = true`
- ❌ No workspace config, theming, or credentials — Slack manages its own state
- ❌ Not the terminal client — see `domains/home/apps/slack-cli/`

## Structure
- `index.nix` — mkSimpleApp call declaring name, description, and package

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
