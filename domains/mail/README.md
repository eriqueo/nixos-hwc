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
│   ├── index.nix              # khal + vdirsyncer integration; extraVdirsyncerPairs option
│   └── parts/
│       ├── khal.nix           # Calendar config
│       ├── vdirsyncer.nix     # iCloud CalDAV config (+ appends sibling pairs)
│       └── service.nix        # vdirsyncer sync timer (shared by calendar + tasks)
├── tasks/
│   ├── index.nix              # VTODO/Reminders sync + todoman (shares calendar config/timer)
│   └── parts/
│       ├── vdirsyncer-pair.nix # [pair tasks] fragment (item_types = ["VTODO"])
│       └── todoman-config.nix  # ~/.config/todoman/config.py
├── mbsync/
│   ├── index.nix              # mbsync module
│   └── parts/
│       ├── render.nix         # .mbsyncrc generation from account attrset
│       └── service.nix        # sync-mail script + systemd service + timer
├── msmtp/
│   ├── index.nix              # SMTP send module
│   └── parts/render.nix       # msmtp config generation
├── health/
│   └── index.nix              # Health monitoring (GPG→pass→Bridge→mbsync→freshness)
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
- 2026-06-24: aerc now builds from the **forked `github:eriqueo/aerc`** flake input
  instead of `pkgs.aerc` — a **zero-change canary** (the fork's `flake.nix` is
  `pkgs.aerc.overrideAttrs { src = self; }` pinned to the `0.21.0` tag, so
  filters/stylesets/man pages/wrapper come out byte-identical; `vendorHash`
  reused, no Go-dep change). Wiring mirrors khalt: new `aerc` flake input
  (`inputs.nixpkgs.follows`), new `domains/mail/aerc/package.nix`
  (`inputs.aerc.packages.${pkgs.system}.default`), `index.nix` threads `inputs`
  and computes `aercPkg`, and `parts/config.nix` swaps all 8 `pkgs.aerc`
  references → `aercPkg`. No behaviour change; this lands the packaging pipeline
  ahead of the upcoming config-gated **which-key** leader popup + msglist column
  headers (both default-off). Rollback = revert these files + drop the input
  (one commit, zero residue).
- 2026-06-24: Added a permanent **digest shield** to the post-new hook (`notmuch/parts/hooks.nix`). Server-generated Market-Intelligence weekly briefs are self-addressed (sent from an HWC address to the user's own inbox), so Proton Bridge saves a copy in `proton/Sent`; the folder-state rule `+sent -inbox -- path:proton/Sent/**` then stripped the `inbox` tag and MailMover (`'NOT tag:inbox':proton/Archive`) archived them. The shield reasserts `+inbox -archive -sent` for `tag:new` self-sent mail (`from:eric@/office@/admin@iheartwoodcraft.com`) whose subject is `"weekly brief"` or `"Weekly Intelligence Digest"`, so the briefs land and stay in the inbox. Parallels the keep shield; runs after `accountTags`, before `removeNew`.
- 2026-06-24: aerc view + readability overhaul. Fixed the main contrast bug — the
  `[user] default` style was dim `fg3` slate (unreadable on dark bg for every
  uncategorized message); now the palette `fg1`. Added scoped views (`focus`
  [new default], `today`, `week`, `people`) + colour-grouped **family aggregates**
  (`business`=work/office/hwcmt, `money`=finance/bank/insurance, `growth`,
  `system`) + `family`/`keep`/`all`/`newsletters`/`notifications`, so the sidebar
  leads with manageable views instead of the 4.6k `inbox_i` firehose. `folders-sort`
  reordered; existing per-tag folders kept (binds unchanged). Note: aerc 0.21 has
  NO column-header feature (`index-columns` defines columns but renders no header row).
- 2026-06-23: Persisted the Gmail-cleanup rules declaratively. New `hwc.mail.notmuch.rules.archiveSenders` option (parallels `trashSenders`) → `+archive -inbox` on `tag:new`. `profiles/mail/home.nix` now sets `trashSenders` (lead-gen/marketing/social) + `archiveSenders` (retail/coaching/bulk) from the 2026-06 backlog audit, so future noise auto-classifies out of the inbox. Both destructive rules are `NOT tag:keep`-guarded, and the post-new hook gained a permanent **keep shield** (`-trash` for `tag:keep AND tag:trash`) so family/friends (`+keep`) can never be auto-trashed (e.g. by afew re-tagging a kept msg that also sits in a Trash folder). aerc gained a non-inbox-scoped **`keep_k`** virtual folder (`tags.nix` flagTags) surfacing the full ~4.4k family/friends archive.
- 2026-06-22: Enabled IMAP sync for both Gmail accounts (`gmail-personal`, `gmail-business`) for a one-time backlog cleanup into notmuch. `sync.enable false→true`; wildcards bounded to `[ "INBOX" ]` only (NOT `[Gmail]/*`) to avoid pulling the `[Gmail]/All Mail` archive superset (~tens of thousands, duplicated against Proton-forwarded copies via Message-ID). Gmail "archive" = expunge from the INBOX channel (message survives in All Mail). First sync verified additive (Create Near). App passwords in `gmail-{personal,business}-password` agenix secrets confirmed valid via IMAP probe.
- 2026-06-11: Added `tasks/` — VTODO/Reminders sync via vdirsyncer + todoman CLI. Contributes a `[pair tasks]` (item_types=["VTODO"]) to the calendar vdirsyncer config via new `hwc.mail.calendar.extraVdirsyncerPairs`, so there's one config file and one sync timer. Reuses calendar's icloud account + apple-app-pw secret. TUI (`todui`) deferred to Phase B.
- 2026-06-09: Removed orphan `protonmail-bridge/` (sys.nix-only clone of `bridge/sys.nix` under a different namespace, imported nowhere; flagged by audit as a latent duplicate `systemd.services.protonmail-bridge` definition). `bridge/` remains the canonical module; `protonmail-bridge-cert/` kept (unique cert-export logic).
- 2026-04-25: Bridge restart resilience — Restart=always, StartLimitBurst=10/3600s, RestartSec=30 (was on-failure/5s with default 5/10s limit). Health check: stable cooldown fingerprints (strip numbers before hashing), auto-restart bridge on failure, purge stale cooldowns after 7 days. Fixes Apr 2-5 incident (67 spurious critical alerts, 3 days unrecovered downtime)
- 2026-04-02: Fix sync-mail to tolerate mbsync partial failures — `notmuch new` now always runs even when Bridge rejects messages. Prevents cascading duplicate copy bug in label copy-back (1833 orphan copies accumulated before fix)
- 2026-03-23: Domain refactor — moved aerc from apps/ to mail/ (hwc.mail.aerc); consolidated bridge services (protonmail-bridge/ + protonmail-bridge-cert/ merged into bridge/sys.nix); deleted 6 stale migration docs; removed dead aerc files (behavior.nix, session.nix)
- 2026-03-19: Add label copy-back to sync-mail (tags→Labels/ Maildir→Proton two-way sync); fix protonLabelTags to not require tag:new; add trashSenders option; remove dead code
- 2026-02-28: Added README for Charter Law 12 compliance
