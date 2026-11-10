# gpg

## Purpose
Configures GPG plus the user gpg-agent (SSH support, GUI pinentry — Qt on secret-service hosts, GNOME3 elsewhere — 2h passphrase cache) and makes `pass` the default password store; optionally bridges pass to the org.freedesktop.secrets D-Bus API so Electron/Chromium apps use GPG-encrypted storage instead of the weak `basic` fallback. Enable via `hwc.home.apps.gpg.enable`.

## Boundaries
- ✅ `programs.gpg`, `services.gpg-agent`, `PASSWORD_STORE_DIR` session var, per-shell `GPG_TTY` export in zsh, `pass` + `gnupg` packages, opt-in `services.pass-secret-service` via `secretService.enable` (graphical hosts only — leave off on headless), and the one decision for stale GnuPG locks (`hwc-gpg-stale-lock`, exposed as `staleLock.package`; mail-health calls it).
- ❌ Does not create or populate the pass store or GPG keys; agenix system secrets are a separate mechanism (`domains/secrets/`).

## Structure
- `index.nix` — options (`enable`, `secretService.enable`, `staleLock.{enable,package}`), gpg/gpg-agent config, pass env, zsh GPG_TTY, pass-secret-service toggle bound to `graphical-session.target`, the `hwc-gpg-stale-lock` helper and its `gpg-stale-lock` oneshot (before `basic.target`).
- Verification: `gpg-stale-lock` in `domains/home/verification/checks.nix` runs the helper against a real keyboxd.

## Stale locks
A crash leaves keyboxd's lifetime lock (`public-keys.d/pubring.db.lock`). GnuPG keeps waiting while the lock's PID exists, and after a reboot that PID can belong to another process, so every keybox read times out. `hwc-gpg-stale-lock --check|--apply` treats a lock as stale when it predates this boot and its PID does not hold the protected file open, or when its PID is gone and the lock is 15+ minutes old. `--apply` removes it with `gpgconf --unlock`. Manual use: `hwc-gpg-stale-lock --check`. Remove the helper once GnuPG detects locks from an earlier boot itself.

## Changelog
- 2026-11-10: Add `hwc-gpg-stale-lock` and the `gpg-stale-lock` login oneshot. A lock left by the 2026-11-10 crash had its PID reused after reboot and blocked every keybox read.
- 2026-11-10: Secret-service hosts use pinentry-qt. pinentry-gnome3 needs GNOME's gcr prompter on D-Bus; without it, it fell back to curses and every service unlock failed.
- 2026-11-10: pass-secret-service now starts with `graphical-session.target` instead of `default.target`. Started early, it had no display, so pinentry could not prompt for a locked key.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
