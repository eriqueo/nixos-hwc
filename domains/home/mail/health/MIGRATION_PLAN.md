# Mail Domain Migration Plan

## Goal

Move the mail infrastructure from `domains/home/mail/` (laptop-centric, Home Manager) to `domains/mail/` (server-primary, still Home Manager but top-level domain).

## Why

- Mail should run on the server 24/7, not depend on laptop lid being open
- Health monitoring, Bridge, and mbsync benefit from server's always-on nature
- Ties into server monitoring stack (ntfy, n8n, Prometheus if needed later)
- aerc accessed via SSH + tmux from laptop (thin client)

## Current State

```
domains/home/mail/           # Home Manager modules under hwc.home.mail.*
├── index.nix                # Auto-loader + account options
├── accounts/                # Proton, Gmail account definitions
├── aerc/                    # Terminal email client config
├── afew/                    # Auto-tagging
├── bridge/                  # Proton Bridge (user + system services)
├── calendar/                # khal + vdirsyncer
├── mbsync/                  # IMAP sync + sync-mail script + timer
├── msmtp/                   # SMTP sending
├── notmuch/                 # Indexing, hooks, tagging rules
├── health/                  # NEW: monitoring (this session)
└── parts/                   # Shared helpers
```

## Target State

```
domains/mail/                # Top-level domain (still Home Manager under the hood)
├── index.nix                # Auto-loader, hwc.mail.* options
├── README.md
├── accounts/                # Account definitions (unchanged)
├── sync/                    # mbsync + notmuch + afew (the pipeline)
│   ├── mbsync/
│   ├── notmuch/
│   └── afew/
├── bridge/                  # Proton Bridge service
├── send/                    # msmtp sending config
├── client/                  # aerc config (consumed by both server + laptop)
├── health/                  # Monitoring + alerting
├── calendar/                # khal + vdirsyncer
└── parts/                   # Shared helpers
```

## Migration Strategy

### Phase 0: Health Module (this session) ✅
- Add `health/` to existing `domains/home/mail/`
- Zero risk, purely additive

### Phase 1: Namespace + File Move (Claude Code session)
- `git mv domains/home/mail/ domains/mail/`
- Update all imports in profiles/home.nix, profiles/system.nix, machine configs
- Rename `hwc.home.mail.*` → `hwc.mail.*` across all modules
- Test: `nixos-rebuild build` on both laptop and server

### Phase 2: Enable on Server
- Add mail profile to server machine config
- Enable Bridge, mbsync, notmuch, health on server
- Migrate GPG key + pass store to server
- Test full pipeline: Bridge → mbsync → notmuch → mail arrives

### Phase 3: aerc via SSH
- Set up tmux/zellij session on server for aerc
- Configure SSH alias: `ssh -t homeserver 'tmux attach -t mail || tmux new -s mail aerc'`
- Test reading, sending, tagging, sync from laptop over Tailscale

### Phase 4: Decommission Laptop Mail
- Disable mail modules on laptop profile
- Keep msmtp for send-only (optional)
- Laptop becomes thin client only

## Risks

- GPG key migration: need to export/import carefully, test pass decryption
- Bridge account re-setup: will need CLI login on server
- UIDVALIDITY: fresh mbsync on server = full re-download (~577MB)
- Dual-running period: both laptop and server syncing could cause conflicts

## Not In Scope

- Changing the mail pipeline architecture (still Proton Bridge → mbsync → notmuch → aerc)
- Switching away from Home Manager (it's the right tool for user-scoped services)
- MCP server integration (low priority, future session)
