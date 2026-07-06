# gpg

## Purpose
Configures GPG plus the user gpg-agent (SSH support, GNOME3 pinentry, 2h passphrase cache) and makes `pass` the default password store; optionally bridges pass to the org.freedesktop.secrets D-Bus API so Electron/Chromium apps use GPG-encrypted storage instead of the weak `basic` fallback. Enable via `hwc.home.apps.gpg.enable`.

## Boundaries
- ✅ `programs.gpg`, `services.gpg-agent`, `PASSWORD_STORE_DIR` session var, per-shell `GPG_TTY` export in zsh, `pass` + `gnupg` packages, opt-in `services.pass-secret-service` via `secretService.enable` (graphical hosts only — leave off on headless).
- ❌ Does not create or populate the pass store or GPG keys; agenix system secrets are a separate mechanism (`domains/secrets/`).

## Structure
- `index.nix` — options (`enable`, `secretService.enable`), gpg/gpg-agent config, pass env, zsh GPG_TTY, pass-secret-service toggle.

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
