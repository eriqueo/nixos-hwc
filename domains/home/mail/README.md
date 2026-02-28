# Home Mail

## Purpose
Email client configuration and account management.

## Boundaries
- Manages: Email accounts, IMAP/SMTP settings, mail client integration
- Does NOT manage: ProtonMail Bridge → `system/services/protonmail-bridge/`

## Structure
```
mail/
├── index.nix    # Mail configuration
└── options.nix  # Mail options
```

## Changelog
- 2026-02-28: Added README for Charter Law 12 compliance
