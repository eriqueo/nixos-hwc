# Home Mail

## Purpose
Self-contained email domain: client UI, accounts, sync, indexing, sending, and bridge services.

## Boundaries
- Manages: aerc UI, accounts, IMAP sync (mbsync), SMTP (msmtp), indexing (notmuch), tagging (afew), Proton Bridge (user + system services), calendar sync, address book
- Does NOT manage: Other mail clients (neomutt, betterbird) → `apps/`

## Structure

Radicale clients in `calendar`, `tasks`, and `contacts` render credential argv
from `domains/lib/hm.nix`, also consumed by todui's list-deletion launcher.
```
mail/
├── index.nix                  # Mail module auto-loader + account options
├── accounts/
│   ├── index.nix              # Account definitions (proton, gmail-personal, gmail-business)
│   └── helpers.nix            # Shared helpers (loginOf, rolesFor, passCmd, etc.)
├── abook/index.nix            # Address book config
├── aerc/
│   ├── index.nix              # aerc module (enable toggle, packages, activation)
│   ├── package.nix            # Forked aerc package from the flake input
│   └── parts/
│       ├── config.nix         # aerc.conf, accounts.conf, queries, stylesets, templates
│       ├── binds.nix          # Keybindings + ov pager config
│       ├── appearance.nix     # Palette-driven styleset
│       ├── tags.nix           # Taxonomy adapter for queries, styles, and bindings
│       ├── tags-custom.json   # User-defined aerc-only tags
│       ├── sieve.nix          # Sieve script deployment
│       └── sieve-filters.nix  # Server-side Sieve rules
├── afew/
│   ├── index.nix              # afew config generation (filters, MailMover)
│   └── package.nix            # afew package derivation
├── bridge/
│   ├── index.nix              # Proton Bridge HM user service
│   ├── sys.nix                # Proton Bridge NixOS system service (+ cert export) + `relay` (socat SMTP/IMAP between hosts)
│   └── parts/
│       ├── files.nix          # keychain.json + setup script
│       ├── runtime.nix        # Env vars, PATH handling
│       └── service.nix        # systemd user service unit
├── classifier/
│   ├── index.nix              # aerc-facing correction/review command
│   └── sys.nix                # pinned Laya + local Nomic hybrid service
├── calendar/
│   ├── index.nix              # khal + vdirsyncer integration; extraVdirsyncerPairs option
│   └── parts/
│       ├── khal.nix           # Calendar config
│       ├── vdirsyncer.nix     # Radicale CalDAV config (+ appends sibling pairs)
│       └── service.nix        # vdirsyncer sync timer (shared by calendar + tasks)
├── tasks/
│   ├── index.nix              # VTODO sync against Radicale + todoman (shares calendar config/timer)
│   └── parts/
│       ├── vdirsyncer-pair-radicale.nix # [pair tasks_radicale] fragment
│       └── todoman-config.nix  # ~/.config/todoman/config.py
├── mbsync/
│   ├── index.nix              # mbsync module
│   └── parts/
│       ├── render.nix         # .mbsyncrc generation from account attrset
│       └── service.nix        # locked core/Trash sync lanes, services, timers, bounded status
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
        ├── searches.nix       # saved searches for notmuch CLI
        └── dashboard.sh       # mail-dashboard script
```

## Aerc workflow contract

`DO` is the inbox-zero queue; `DID` waits after Eric acted; `LOOK` needs no
response; `JUNK` is recoverable Trash. Reading never changes workflow state.
Archive records completion and removes every active state. Single-key
archive/trash uses aerc's marked-or-selected rule: `J`/`K` selections move as
one thread-wide batch, and a selected folded row expands to its whole thread.
Domain (`hwc`, `datax`, `family`, `personal`, `other`) is independent of State,
appears as a column, and is filtered rather than exposed as folders. Facts are
additive Tags and never control placement. `Space g A` opens all non-trash
history. `Space f t` filters by tag, `Space f d …` filters by Domain, and
`Space f c` clears the current filter.
Sort with `Space s d` (newest), `Space s f` (sender), or `Space s s` (subject).

State and Domain corrections teach the classifier's exact-sender preference in
the same operation. `DID` and completion are never generalized. No separate
sender-rule writer runs in the arrival hook.

Persistent routing rules are narrower than sender learning: each one requires
an exact sender plus subject text, then chooses State and Domain. Create one from
the selected message with `Space r a`; review or disable rules with `Space r m`.
Rules live as append-only events in the classifier ledger, and Junk rules ask
for an extra confirmation before they can send future matches to Trash.

Future Workbench integration should consume the same selected-item context
contract used by the existing hubs: a global action can hand the selected
mail/task/document to an agent with a stable source and item ID. That action is
deliberately not part of this mail slice; any write-back must remain an explicit
review/apply step.

## Known Issues

### Proton Bridge "known recovered message" rejections
Proton Bridge (v3.21.x) occasionally refuses APPEND for messages it considers duplicates of "recovered messages" (error code 2501). This causes mbsync to exit non-zero. As of 2026-04-02, sync-mail tolerates mbsync partial failures so that `notmuch new` always runs — this prevents a cascading bug where un-indexed label copies trigger infinite re-copying by the label copy-back loop. The mbsync exit code is still propagated to systemd for monitoring visibility.

## Changelog

- 2026-09-25: Service split wave 3 (notifications): `health/` — `notify.url` defaults to the system's `hwc.notifications.notify.url` (osConfig), so neither machine sets it.
- 2026-09-25: `calendar/parts/service.nix` — the discover-on-change step also runs `vdirsyncer metasync` (and its version is part of the stamp, so it runs once everywhere). `sync` never moves collection metadata; hwc-work had no displaynames, so khal rejected `default_calendar = hwc` and the morning briefing's calendar gather broke.
- 2026-09-25: `calendar/parts/service.nix` — vdirsyncer's pre-sync discover now runs whenever its config differs from the last discovered one (sha256 stamp beside `status/`), not only on an empty status dir: moving the Radicale mirror collections to hwc-work changed the pair config and every sync failed with "Detected change in config file, please run discover".
- 2026-09-25: `calendar/parts/service.nix` — vdirsyncer runs a guarded first-run
  `discover` (only while `status/` is missing or empty) before `sync`. A new host
  (hwc-work, service split wave 2) otherwise fails every run with "Please run
  `vdirsyncer discover`"; later runs never re-discover, so a collection deleted on
  one side is not re-created.
- 2026-09-25: Service split wave 2 — the Proton Bridge session moved from
  hwc-server to hwc-work. `bridge/index.nix` now honours `hwc.mail.bridge.enable`
  (it used to key only on "a proton-bridge account exists"; unit presence already
  equalled `enable` on every host, so nothing else changed) and the mail role sets
  it with `mkDefault`. New `hwc.mail.bridge.relay` (`bridge/sys.nix`): one socat per
  port, `listenAddress → targetAddress`; work exposes its bridge on its tailnet IP,
  hwc-server relays its own `127.0.0.1:1025/1143` there so its consumers are
  unchanged. `health/`: the bridge-unit check and vault check run only where the
  bridge is local, and the port checks now require the IMAP `* OK` / SMTP `220`
  greeting (a relay port accepts a bare connect even when the bridge is down).
- 2026-09-24: Calendar and tasks sync only against Radicale. Deleted the iCloud
  code paths (calendar `accounts`, tasks `icloud.enable`/`account`/`collections`,
  both `radicale.enable` switches, the apple-app-pw handshake); the mail role no
  longer declares an iCloud account. See `calendar/` and `tasks/` changelogs.
- 2026-09-24: Added guided sender-plus-subject routing rules under `Space r`.
  Rules share the classifier ledger, preserve thread-level safety overrides,
  and publish their reason into Workbench and morning-briefing views.
- 2026-09-23: Kept aerc's Domain, State, and Tags columns loadable by preserving
  whitespace between generated `case` and `exclude` template operands.
- 2026-09-22: Promoted the private Nomic embedding classifier for Domain after
  it passed the frozen sender-disjoint gate (6/7). Embedding State remains
  shadow-only after missing its gate (5/7); Laya and learned exact-sender
  preferences still control State. The service now waits for and requires the
  loopback-only `llama-embed` dependency.
- 2026-09-22: Isolated Proton Trash from the ten-minute core sync. `sync-mail`
  now owns one nonblocking lock and a versioned, atomically replaced status
  projection; core runs every ten minutes, and Trash is a daily pull-only mirror
  because Bridge refuses IMAP APPEND into Trash. Trash-only runs never invoke
  MailMover. The false-success cache marker was removed. `notmuch new` still runs
  after partial IMAP failures to preserve the label-copy safety invariant.

- 2026-09-22: Mail workflow v2 makes State, Domain, Tags, and completion
  disjoint. All human state/outcome changes pass through the classifier ledger;
  Laya can assign only DO/LOOK/JUNK and reopens DID/completed on a new reply.
- 2026-09-21: Made `<Space>tt` toggle the selected thread fold and
  `<Space>tT` fold the current view. Restored native marked-or-selected
  archive/trash behavior so `J`/`K` selections move as a batch.
- 2026-09-21: Initially forced `a` and `d` onto the selected thread to prevent
  partial completion. Superseded above because clearing marks broke `J`/`K`
  batches; explicit folding now supplies the whole-thread boundary.
- 2026-09-21: Added the local Laya mail classifier boundary. System One owns
  typed model questions, conservative policy, human locks, and the append-only
  case ledger; this domain pins its source/model revisions, runs one bounded
  resident CPU worker with the explicit CPU-only PyTorch build, and exposes
  reviewed aerc correction commands. The
  CRITICAL ledger is backed up under `/var/lib/hwc`; the model cache is
  REPLACEABLE, isolated from the user's home, and bounded by tmpfiles cleanup.
- 2026-09-15: Restored `hwc` as the stable display name and khal default for
  the primary `eric/work` calendar. Aerc's reviewed `i` import and `busy` now
  derive that name from one value, while CRM and CalDAV keep using the
  collection path.
- 2026-09-15: Separated inbox zero from durable organization. `now` remains the
  stable queue of undecided mail while `family`, `datax`, and `hwc` now retain
  archived history; all non-trash mail is one key away. Added default
  newest-first ordering, sender/subject sorts, and documented tag filtering.
  Added reviewed exact-sender rules from aerc with a private, versioned,
  append-audited SQLite ledger, bounded grouped notmuch writes, `keep`
  protection, backed-up server state, and interactive rule disabling.
- 2026-09-15: Made aerc's sender-authored plain MIME part the calm default.
  Plain mail now has a fixed reading measure, bounded whitespace, terminal
  control sanitization, and compact clickable labels for long tracking URLs;
  HTML remains available through MIME-part navigation.
- 2026-09-15: Made aerc's email-only unsubscribe path explicit and review-first.
  `<Space>fu` now asks before creating the draft, bypasses Neovim, and still
  requires `y` on the review screen before anything is sent.
- 2026-09-15: Made aerc's tag controls match the calm inbox model: the first
  mark popup is bounded, categories and visible flags are nested,
  automation-only action/pending tags stay out of the human workflow, tag
  filtering has completion and a reusable all-mail query, and bulk clears
  preserve protected `keep`. Aerc tab navigation now uses Alt+h/l and accepts
  both terminal encodings of the Alt+Shift+j/k compatibility chords. The fork
  pin now routes IPC commands through aerc's UI loop so remote configuration
  reloads cannot race a tab redraw and crash the client.
- 2026-09-14: Kept navigation layers distinct: Workbench/Zellij retains Ctrl
  chords, while aerc previous/next-tab now uses Alt+Shift+K/J in the message,
  viewer, compose, and terminal contexts. Selector prompts from the aerc fork
  now render as bounded raised cards with a visible key legend; the
  unsubscribe flow labels HTTPS as recommended and email as fallback.
- 2026-09-14: Improved the calendar handoff for image-based campaign mail.
  Written dates in subjects populate the review form without inventing a
  midnight start; generic and tracked links no longer become locations; the
  title drops a duplicated trailing date; and the reference section retains
  only one labeled event-page candidate without resolving tracking redirects.
  When missing facts are trapped inside a large remote flyer, the helper offers
  an explicit opt-in to fetch that public HTTPS image once and run bounded local
  Tesseract OCR before the editable review.
- 2026-09-14: Repaired the managed-mail lifecycle. `now` is now the stable
  `queue` + `inbox` cohort, so opening a message cannot make it disappear. New
  mail once again gets the transient `new` tag required by every arrival rule;
  folder-state tagging now runs before sender disposition; and finance tagging
  no longer de-inboxes receipts. The legacy Inbox remains outside the managed
  queue for bounded later cleanup.
- 2026-09-14: Learned exact QuickBooks-marketing and Bozeman Daily Chronicle
  e-edition sender addresses as future auto-trash noise without matching the
  separate QuickBooks payment sender.
- 2026-09-14: Interactive aerc archive/trash now mean a completed decision:
  preserve-or-delete, remove from inbox, and clear unread. Automated arrival
  rules remain unchanged.
- 2026-09-14: Refined aerc's calm surface to four visible contexts: `now`,
  `family`, `datax`, and `hwc`. The three context folders exactly partition
  `now` with DataX-first precedence and HWC as the safe fallback. Backlog and
  system destinations remain reachable by Space-leader navigation without
  occupying the sidebar.
- 2026-09-14: Replaced aerc's overlapping-folder dashboard with a calm daily
  surface: `now` (recent unread non-noise), `family`, `backlog`, drafts, sent,
  archive, and trash. Only `now` shows a sidebar count and the tab count is
  scoped to it; the message list is a
  compact state/date/from/subject view without category-wide row colors. Legacy
  queries and triage tags remain available for integrations and direct
  drill-down. Replaced the inert local trash-sender helper with aerc's built-in
  `:unsubscribe` command.
- 2026-09-07: Share the Radicale password selector with todui; retain per-user
  selection and colon-containing passwords across the three sync clients.
- 2026-08-30: `accounts/index.nix` Gmail agenix handshake no longer falls back to
  `/dev/null`. Under standalone HM (`hms`) there is no `osConfig`, so both Gmail
  `PassCmd`s rendered `tr -d "\n" < /dev/null`, mbsync skipped both accounts with
  "PassCmd produced no output", and `mbsync.service` exited 1 every 10 minutes on
  hwc-server (first failure 2026-08-26 15:54). Fallback is now the canonical
  runtime path `/run/agenix/gmail-{personal,business}-password`, matching the
  handshake `calendar/index.nix` and `tasks/index.nix` already use and the literal
  `domains/automation/mail-janitor/index.nix` already hardcodes. Also deleted the
  dead `parts/common.nix` — byte-identical to `accounts/helpers.nix`, zero
  importers since it was added, and a second producer of `passCmd` that a fix
  could have landed in harmlessly.
- 2026-07-11: mbsync/afew: maildir-root fallback literal `/home/eric/400_mail` replaced with the `${config.home.homeDirectory}/400_mail` derivation (aerc precedent; Law 3 migration, rendered value unchanged).
- 2026-07-09 (b): aerc joins triage (unified-triage Phase 2) — `triage/*`
  virtual folders (taxonomy-generated, tree-nested, inbox-scoped) +
  `<Space>tu/tr/tn` set-bucket binds (replace-set, same semantics as the
  gateway's `hwc_mail set-triage`) + `<Space>gU/gR/gN` go-tos. The server
  notmuch DB is canonical by design (laptop "aerc" is an SSH alias into the
  server's aerc), so no cross-machine tag sync is needed.
- 2026-07-09: New `taxonomy/` library (pure data + derivations) — single
  source of truth for tag vocabulary, triage buckets, and sender
  dispositions. `notmuch` rule defaults, `aerc/parts/tags.nix`, the MCP
  gateway constants, and the mail-triage prompt's sender lists all derive
  from it at build time (drift-kill; see
  docs/plans/unified-triage-architecture.md). `profiles/mail/home.nix`
  inline sender lists moved into `taxonomy/data.nix` verbatim.
- 2026-07-06: mail-health criticals rewired to hwc-notify priority 1 (Discord ×2 + email fanout) alongside the existing Slack webhook; new `notify.url` option (server sets loopback :11600). Closes the paging gap left by the gotify decommission.
- 2026-07-06: msmtp logfile → ~/.local/state/msmtp.log; the old ~/.config/msmtp/msmtp.log was itself an HM store file (read-only), so msmtp warned on every single send.
- 2026-07-06: Gotify decommission — mail health critical alerts no longer push via hwc-gotify-send (`hwc.mail.health.gotify.tokenFile` removed); criticals now route to the n8n webhook → Slack path alongside warnings.
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
