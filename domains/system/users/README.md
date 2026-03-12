# System Users

## Purpose
User account declarations and group memberships.

## Boundaries
- Manages: users.users declarations, group memberships, shell assignment
- Does NOT manage: User environment → `home/`, identity options → `core/identity/`

## Structure
```
users/
├── eric.nix      # Primary user account
└── index.nix     # Users aggregator (options inlined)
```

## Changelog
- 2026-02-28: Added README for Charter Law 12 compliance
- 2026-03-12: Inlined options.nix into index.nix; removed separate options.nix
