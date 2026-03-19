# Home Mail

## Purpose
Email client configuration and account management.

## Boundaries
- Manages: Email accounts, IMAP/SMTP settings, mail client integration
- Does NOT manage: ProtonMail Bridge → `system/services/protonmail-bridge/`

## Structure
```
mail/
├── index.nix                  # Mail module auto-loader + account options
├── parts/common.nix           # Shared helpers (loginOf, rolesFor, passCmd, etc.)
├── accounts/index.nix         # Account definitions (proton; gmail commented out)
├── afew/
│   ├── index.nix              # afew config generation (filters, MailMover)
│   └── package.nix            # afew package derivation
├── mbsync/
│   ├── index.nix              # mbsync module
│   ├── parts/render.nix       # .mbsyncrc generation from account attrset
│   └── parts/service.nix      # sync-mail script + systemd service + timer
├── notmuch/
│   ├── index.nix              # notmuch module + options
│   └── parts/
│       ├── config.nix         # notmuch config (database, user, flags)
│       ├── hooks.nix          # post-new hook generator
│       ├── paths.nix          # maildirRoot resolution
│       ├── identity.nix       # userName/email/newTags defaults
│       ├── folders.nix        # folder→tag clause builder (uses common.rolesFor)
│       ├── rules.nix          # newsletter/notification/finance/action/trash rules
│       ├── searches.nix       # saved searches for notmuch CLI
│       └── dashboard.sh       # mail-dashboard script (installed if installDashboard=true)
└── protonmail-bridge/sys.nix  # ProtonMail Bridge system service
```

## Changelog
- 2026-03-19: Add label copy-back to sync-mail (tags→Labels/ Maildir→Proton two-way sync); fix protonLabelTags to not require tag:new (picks up Proton-web label changes on existing messages); add trashSenders option; remove dead rules.sh and sample.sh; clean up render.nix dead code (escapeSquareBrackets, expandGoogleAliases, empty certFile/tlsFingerprint)
- 2026-02-28: Added README for Charter Law 12 compliance
