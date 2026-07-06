# n8n

## Purpose
Installs the n8n workflow-automation CLI/runtime as a local (Home Manager) package and sets its runtime tuning via session variables: settings-file permission enforcement, SQLite pool size, task runners enabled, env access in Node allowed.

## Boundaries
- ✅ Manages: `hwc.home.apps.n8n.enable` → `pkgs.n8n` on `home.packages` + four `N8N_*`/`DB_*` session variables.
- ❌ Does not manage: a systemd service or reverse-proxy route (n8n is launched manually here; the server-hosted automation stack lives in `domains/automation/n8n/`), nor workflows/credentials (n8n's own data dir).

## Structure
- `index.nix` — options, package install, `home.sessionVariables` for n8n runtime flags.

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
