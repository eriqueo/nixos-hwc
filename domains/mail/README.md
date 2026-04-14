# Home Mail

## Purpose
Self-contained email domain: client UI, accounts, sync, indexing, sending, and bridge services.

## Boundaries
- Manages: aerc UI, accounts, IMAP sync (mbsync), SMTP (msmtp), indexing (notmuch), tagging (afew), Proton Bridge (user + system services), calendar sync, address book
- Does NOT manage: Other mail clients (neomutt, betterbird) → `apps/`

## Structure
```
mail/
├── index.nix                  # Mail module auto-loader + account options
├── accounts/
│   ├── index.nix              # Account definitions (proton, gmail-personal, gmail-business)
│   └── helpers.nix            # Shared helpers (loginOf, rolesFor, passCmd, etc.)
├── abook/index.nix            # Address book config
├── aerc/
│   ├── index.nix              # aerc module (enable toggle, packages, activation)
│   └── parts/
│       ├── config.nix         # aerc.conf, accounts.conf, queries, stylesets, templates
│       ├── binds.nix          # Keybindings + ov pager config
│       ├── tags.nix           # Single source of truth for tag definitions
│       ├── theme.nix          # Palette-driven styleset (Gruvbox)
│       └── sieve.nix          # Server-side sieve filters
├── afew/
│   ├── index.nix              # afew config generation (filters, MailMover)
│   └── package.nix            # afew package derivation
├── bridge/
│   ├── index.nix              # Proton Bridge HM user service
│   ├── sys.nix                # Proton Bridge NixOS system service (+ cert export)
│   └── parts/
│       ├── files.nix          # keychain.json + setup script
│       ├── runtime.nix        # Env vars, PATH handling
│       └── service.nix        # systemd user service unit
├── calendar/
│   ├── index.nix              # khal + vdirsyncer integration
│   └── parts/
│       ├── khal.nix           # Calendar config
│       ├── vdirsyncer.nix     # Google Calendar OAuth setup
│       └── service.nix        # vdirsyncer sync timer
├── mbsync/
│   ├── index.nix              # mbsync module
│   └── parts/
│       ├── render.nix         # .mbsyncrc generation from account attrset
│       └── service.nix        # sync-mail script + systemd service + timer
├── msmtp/
│   ├── index.nix              # SMTP send module
│   └── parts/render.nix       # msmtp config generation
└── notmuch/
    ├── index.nix              # notmuch module + options
    └── parts/
        ├── config.nix         # notmuch config (database, user, flags)
        ├── hooks.nix          # post-new hook generator
        ├── paths.nix          # maildirRoot resolution
        ├── identity.nix       # userName/email/newTags defaults
        ├── folders.nix        # folder→tag clause builder (uses common.rolesFor)
        ├── rules.nix          # newsletter/notification/finance/action/trash rules
        ├── searches.nix       # saved searches for notmuch CLI
        └── dashboard.sh       # mail-dashboard script
```

## Known Issues

### Proton Bridge "known recovered message" rejections
Proton Bridge (v3.21.x) occasionally refuses APPEND for messages it considers duplicates of "recovered messages" (error code 2501). This causes mbsync to exit non-zero. As of 2026-04-02, sync-mail tolerates mbsync partial failures so that `notmuch new` always runs — this prevents a cascading bug where un-indexed label copies trigger infinite re-copying by the label copy-back loop. The mbsync exit code is still propagated to systemd for monitoring visibility.

## Changelog
- 2026-04-02: Fix sync-mail to tolerate mbsync partial failures — `notmuch new` now always runs even when Bridge rejects messages. Prevents cascading duplicate copy bug in label copy-back (1833 orphan copies accumulated before fix)
- 2026-03-23: Domain refactor — moved aerc from apps/ to mail/ (hwc.mail.aerc); consolidated bridge services (protonmail-bridge/ + protonmail-bridge-cert/ merged into bridge/sys.nix); deleted 6 stale migration docs; removed dead aerc files (behavior.nix, session.nix)
- 2026-03-19: Add label copy-back to sync-mail (tags→Labels/ Maildir→Proton two-way sync); fix protonLabelTags to not require tag:new; add trashSenders option; remove dead code
- 2026-02-28: Added README for Charter Law 12 compliance
