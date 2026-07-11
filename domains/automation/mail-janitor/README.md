# mail-janitor

## Purpose
Scheduled, age-aware anti-buildup sweep for the Gmail accounts. Stops promo/
transactional cruft from silting up Gmail All Mail over time, the standing
companion to the one-time backlog cleanup.

## Boundaries
- Manages: a weekly systemd timer + oneshot service that classifies Gmail All
  Mail (per account) and trashes the junk.
- Does NOT manage: the local notmuch/aerc inbox rules (those live in
  `domains/mail/notmuch`), the Gmail import filters, or the Family-Friends label.

## Model (three tiers — see `janitor.py`)
- **PRESERVE** — people, history (jobs/school/orgs), finance, anything personal → never touched.
- **TXN** — receipts/orders/bookings → trashed once older than `txnMaxAgeDays` (default 365). Keeps recent receipts for returns/warranty/taxes.
- **NOISE** — promo/streaming/social/newsletters/bot-noise → trashed at any age.

The `Family-Friends` label and Sent are ALWAYS excluded. Action is `UID MOVE →
[Gmail]/Trash` (30-day recoverable); nothing is hard-deleted.

## Structure
```
mail-janitor/
├── index.nix    # hwc.automation.mailJanitor.* options + timer/service
├── janitor.py   # classifier + per-account IMAP sweep + hwc-notify summary
└── README.md
```

## Rollout / safety
- `dryRun` defaults **true**: it reports what it WOULD trash (Discord, topic
  nightly-builds) without touching anything. Verify the reports, then set
  `hwc.automation.mailJanitor.dryRun = false`.
- Runs as `eric` with the `secrets` supplementary group to read the gmail app
  passwords at `/run/agenix/gmail-{personal,business}-password`.
- Heuristic classifier defaults ambiguous senders to PRESERVE (errs toward
  keeping); refine the pattern lists in `janitor.py` as new junk surfaces.

## Changelog
- 2026-07-11: `User = lib.mkForce "eric"` per the native-services Architecture Law (was bare; no-op today, verified by before/after eval).
- 2026-06-24 (b): PRESERVE allowlist (`.gov` filings, `calendar.*` invites, security/
  account alerts) — fixes NOISE false-positives. New **TRIAGE** tier: newsletters
  (`newsletter@`/`news@`/`digest`…) → `Newsletters-Triage` label instead of trash;
  trashed only after `triageMaxAgeDays` (30) IN triage (state-tracked per message-id
  in `stateDir`; clock starts at label time, not send date) unless starred or keep/
  Family-Friends-labeled. Star a newsletter to save it.
- 2026-06-24: Created. Weekly Gmail anti-buildup sweep (NOISE any-age + TXN >1yr),
  Family-Friends-protected, dry-run-first. Productionizes the interactive
  `~/400_mail/_cleanup` sweep into a standing job.
