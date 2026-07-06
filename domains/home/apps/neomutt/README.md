# neomutt

## Purpose
Configures the NeoMutt TUI email client over the shared `hwc.mail.accounts` registry: generates `neomuttrc` (Maildir at `~/400_mail/Maildir`, sidebar with per-account labels, msmtp sending, abook queries), a palette-driven `theme.muttrc`, a leader-key (`,`) keybinding system with auto-generated per-account inbox macros, and a mailcap. If no mail accounts are defined it emits a warning and configures nothing.

## Boundaries
- ✅ Manages: `hwc.home.apps.neomutt.enable`; neomuttrc/theme.muttrc/behavior.muttrc/.mailcap files; companion packages (neomutt, msmtp, isync, notmuch, urlscan, abook, lynx, zathura).
- ❌ Does not manage: account definitions (`hwc.mail.accounts`, mail domain), msmtp/mbsync config and sync timers, or SMTP/IMAP credentials.

## Structure
- `index.nix` — options, account resolution (primary pick), warning path when no accounts, wires part outputs into packages/files.
- `parts/appearance.nix` — neomuttrc (mailboxes, sidebar, pager, msmtp, mailcap wiring), theme.muttrc from theme tokens, `.mailcap` handlers.
- `parts/behavior.nix` — behavior.muttrc: vim-like binds, `,`-leader macro system, generated `,gN` per-account inbox jumps.
- `parts/session.nix` — package list only (no services/env).
- `parts/theme.nix` — adapter: palette → NeoMutt color tokens consumed by appearance.

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
