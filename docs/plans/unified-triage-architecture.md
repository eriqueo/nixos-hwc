# Local mail classification architecture

Status: implemented 2026-09-21. Laya is the first classifier; Jev is deferred.

## Observable contract

Every managed thread has one attention state and one subject category.

- Attention: `act | look | bulk | junk`.
- Subject: `hwc | datax | family | personal | other`.
- Now is `act + look`. Reading does not complete or remove an item.
- `bulk` is read, archived, tagged `later`, and retained indefinitely.
- `junk` is recoverable Trash. The model may choose it only when a strong,
  stable model result agrees with concrete mail evidence.
- Any uncertain or invalid result becomes `act / other` and stays in Now.
- Human attention or category corrections lock the thread permanently.
- An unlocked model decision may run again only after a new message changes the
  thread fingerprint.

Factual tags are additive and do not control placement: `calendar`, `deadline`,
`finance`, `security`, `receipt`, `recurring`, `newsletter`, `unsubscribe`, and
the deterministic `attachment` tag. Attachment contents are not inspected.

## Runtime shape

System One owns the versioned classifier contract, Laya questions, conservative
policy, notmuch effects, and SQLite case ledger. Nix pins both the System One
commit and the exact Laya model revision.

The model runs once as a resident CPU systemd service behind a private Unix
socket. A bounded runner examines the newest message plus two prior messages,
with quotes, signatures, and attachment bodies removed. It asks attention and
category questions in both option orders; disagreement or a weak margin falls
back safely.

The ledger stores stable thread cases, append-only model judgments, append-only
human events, and exact-sender correction counts. The ledger is CRITICAL data
under `/var/lib/hwc/mail-classifier`; the pinned model cache is REPLACEABLE and
cleaned after 30 days of disuse.

## Research basis

The design keeps the useful patterns from the evaluated examples without
copying their mailbox authority:

- Jevmail uses closed questions, stores category probabilities, separates
  corrections from original predictions, and drains a bounded SQLite queue.
- gmail-ai-helper demonstrates local model classification and content-addressed
  caching, but its free-text JSON repair is unnecessary with typed output.
- ai-email-triage puts deterministic rules and caches before model work, matching
  this system's rules-first boundary.
- Nexo Mail separates a read-only mailbox adapter from model providers and
  checks runtime health before accepting work.
- System One already had typed decisions, bounded timeouts, stable content keys,
  and option-order probes. Only a mail-specific benchmark can establish trust.

The inspected revisions and detailed assessment remain preserved in git history
from the Phase 6 design draft this document supersedes.

## User surfaces

- aerc shows Now, five subject views, Later, and Junk.
- `<Space>t a|l|b|j` records a permanent attention correction.
- `<Space>t c h|d|f|p|o` records a permanent subject correction.
- The morning briefing and MCP mail board read the same snapshot and tags.
- Calendar-tagged mail produces a private khal-format draft for human review.
  It never creates or syncs an appointment automatically.
- A persistent CalDAV reminder appears every Thursday at 9am on the phone to
  review Later and Junk, unsubscribe at the source, and add exact sender rules.

## Failure and learning policy

Model or socket failure leaves mail in Now and records a degraded briefing; it
never silently files mail away. Processing is capped per run and repeats every
15 minutes. Each effect is idempotent over a content-derived thread fingerprint.

After two matching human corrections for an exact sender, `mail-classifier
review` proposes a rule. It does not create wildcard or domain rules. A human
must review and install any proposed rule, so learning can grow without turning
one mistaken correction into broad automatic behavior.

## Next evaluation gate

Run Laya long enough to collect human corrections before expanding autonomy.
Measure attention accuracy, unsafe Junk attempts, fallback rate, and correction
rate by exact sender. Only then consider auto-unsubscribe, attachment reading,
30-day Later purging, or a Jev comparison.
