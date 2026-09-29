# Local mail workflow architecture

Status: workflow v2 implemented 2026-09-22. Laya is the first classifier; Jev
remains a future comparison.

## Observable contract

Each managed thread has exactly one active workflow state and one Domain:

- State: `do | did | look | junk`.
- Domain: `hwc | datax | family | personal | other`.
- `DO` means Eric must act and is the inbox-zero queue.
- `DID` means Eric acted and is waiting. Only a human may choose it; a new reply
  reopens the thread to `DO`.
- `LOOK` means read or monitor without a response.
- `JUNK` means unwanted mail in recoverable Trash.
- Archive completes a thread. Completed mail has `workflow/done` and no active
  state, so it cannot reappear from a stale snapshot.

Domain is a filter and column, never a folder or placement rule. Factual traits
are additive and never move mail: `attachment`, `calendar`, `deadline`,
`finance`, `security`, `receipt`, `recurring`, `newsletter`, and `unsubscribe`.
Attachment contents are not inspected.

## Authority and runtime

System One owns the versioned `mail-classifier-v2` contract, Laya questions,
notmuch effects, and SQLite case ledger. Nix pins the System One commit and exact
Laya model revision, then passes that same contract to notmuch, aerc, the
briefing, and MCP.

Laya runs as a resident CPU service on a private Unix socket. It may propose
only `DO`, `LOOK`, or `JUNK`, plus one Domain and factual traits. Uncertain,
invalid, or failed inference remains retryable `DO`; it never becomes a
completed judgment. The model never assigns `DID` or completion.

The CRITICAL ledger under `/var/lib/hwc/mail-classifier` stores content-derived
thread cases, append-only judgments, append-only human events, independent
state/Domain locks, outcomes, and exact-sender learning. Its v1 database is
backed up before the schema-2 migration. The pinned model cache is REPLACEABLE.

Explicit routing rules use that same append-only event ledger; there is no
second aerc or arrival-hook rule store. A rule matches an exact sender plus a
required, case-insensitive subject substring and chooses `DO`, `LOOK`, or
`JUNK` plus one Domain. The most specific matching subject wins. A rule beats
model output and broad exact-sender learning, while a thread-specific human lock
and the new-reply `DO` safety rule remain stronger. Active rules are capped at
200. `JUNK` creation requires a separate confirmation.

## Human controls

- aerc columns are `From | Subject | Date | Domain | State | Tags`.
- `<Space>ta`, `<Space>td`, `<Space>tl`, and `<Space>tj` teach
  `DO`, `DID`, `LOOK`, and `JUNK` through the ledger.
- `<Space>tc h|d|f|p|o` teaches Domain without changing state.
- `<Space>ra` reviews a sender-plus-subject routing rule from the selected
  message; `<Space>rm` reviews and disables active rules.
- `a` completes; `d` directly trashes without sender teaching.
- `J`/`K` marks plus `a`/`d` operate on the complete marked set, thread-wide.
- `<Space>tt` folds the selected thread; `<Space>tT` folds all threads.
- The sidebar contains workflow states only. Domain drill-down uses filters.

The morning briefing is a read-only view of the same v2 snapshot. Routed items
carry a plain-language rule explanation, and the dashboard and email list active
rules. The Workbench mail digest consumes the same item summary. MCP reflects
live `state/*` tags and routes state/outcome writes through the same ledger as
aerc. Calendar mail creates private khal-format drafts for review and never
imports an event automatically.

## Failure and learning policy

Processing is bounded and repeats every 15 minutes. Provider failure leaves the
case visible and retryable. A human correction locks only the axis changed.
Exact-sender learning can reuse human `DO`, `LOOK`, or `JUNK` and Domain
corrections; `DID` is never generalized to future mail. A new message changes
the thread fingerprint and reopens a prior `DID` or completed outcome to `DO`.

Run v2 long enough to measure unsafe Junk attempts, fallback rate, correction
rate, and sender-learning precision before considering attachment reading,
automatic deletion, auto-unsubscribe, or a Jev comparison.

## Proton two-way sync — refined plan, 2026-09-29

S0 is deployed at `20ea1240`, and Eric confirmed the two generated filters were
pasted. Their one-day delivery check remains open. S1–S4 are not implemented.
The corrected handoff contract is triage from both aerc and the Proton phone/web
app, using the same classifier ledger. This adds transport observation and
projection; it does not retune Laya or promote its shadow State model.

### Shape and authority

System One remains the sole owner of workflow State, Domain, human events and
sender learning. Add residency observation to its existing mail command and
ledger. The Nix mail-sync wrapper supplies transport readiness and invokes it
only after afew, mbsync and notmuch indexing succeed. Keep one sync lock.

Use actual file residency for the whole thread, including every physical copy.
Proton label/Sent copies do not count as Inbox/Archive/Trash residency. A thread
with any Inbox copy remains in Inbox; mixed Archive/Trash is ambiguous and does
nothing. Store the previous residency and content-derived message fingerprint.
Only a previously observed Inbox thread leaving it with unchanged fingerprint
can propose completion or Trash. Initial Archive/Trash and changed fingerprints
never infer a human action. A known Archive/Trash thread returning to Inbox can
propose a non-teaching reopen. Existing matching local outcomes are no-ops.

The observer starts in shadow for seven days: it records observations and
proposals, not human actions or model judgments, and never tags or moves mail.
It scans a 30-day window with a ceiling of 2,000 threads and 100 transitions per
run. Overflow halts the batch without advancing snapshots. Older threads are
no-ops. The additive snapshot tables carry sync schema version 1 while leaving
the classifier's schema-2 reader compatible. Snapshots are rebuildable from
current residency with an initial no-action baseline; events remain CRITICAL.

Own identities come from one notmuch identity producer. Include Eric's mail
aliases there and remove the repeated role declarations. The classifier binds
that set at command entry, excludes self from learning and chooses the newest
non-self message for automatic label corrections. Existing own-address
preferences remain in the audit store but cannot influence predictions. A
separate `reopen` command changes a thread to DO without teaching a sender.

### Ordered slices and acceptance

1. Safety prerequisites: guard self-learning, ignore self preferences, add
   non-teaching reopen and a bounded SQLite busy result. Test the actual command
   paths, preserve Domain and audit history, and see the tests fail when the
   guard integration is removed. Run System One's required build and tests.
2. S1 shadow: add versioned observations/proposals to the existing ledger and
   wire the observer after successful mail sync. Test a fixture Maildir with
   multi-folder threads, automatic Archive, reopen, failed afew/sync/indexing,
   out-of-window messages, repeat runs and caps. Removing the observer call must
   fail the shell wiring check. Before deployment, back up the ledger and rehearse
   restore with integrity and row-count checks. The live completion signal is a
   healthy residency status lane and visible thread proposals without mail or
   sender-preference changes. After seven days, compare proposals with actual
   phone actions before allowing live transitions.
3. S2 projection: Eric creates `@look`, `@did`, `@hwc`, `@datax`, `@family`,
   `@personal` when the adapter is ready. Define their mapping once in the
   classifier contract. Exclude `Labels/@*` from mbsync and legacy label tagging.
   An IMAP adapter can COPY or expunge only these label mailboxes. First prove on
   one test message that a label copy does not duplicate All Mail and a label
   expunge preserves Archive. Count duplicates periodically. Track acknowledged
   writes in the ledger; advance projection state only after IMAP OK. Missing
   labels or out-of-window threads cause no writes. Report terminal status in a
   `labels` lane. No real-folder expunge is allowed.
4. S3 label correction: compare remote labels and acknowledged projection at
   thread level. Pending means a label write acknowledged this run but not yet
   observed remotely; these are excluded from human interpretation. Labels on
   Sent or old messages participate in the thread's remote view. Bound human
   corrections to 20 per run, halt on overflow and record actions through the
   existing correction owner. Take and rehearse a separate pre-teaching backup.
   Require no oscillation across three runs and no self-sender learning.
5. S4 consolidation needs Eric's explicit go. Map old labels to the new domains,
   propose coaching/tech/ads/website/aerc as routing candidates, and move finance,
   bank and insurance to the finance trait. Retire interim `02-routing`, legacy
   aerc views and `label:*` searches together. Eric deletes old Proton labels.

Rejected shapes: stateless Archive→done closes Sieve-delivered leads;
`correct --state do` for reopen teaches instead of merely reopening; IMAP custom
keywords do not persist; both mbsync and the direct adapter writing managed label
folders create two writers. Keep the current model thresholds frozen. New model
promotion requires fresh chronological, sender-disjoint corrections and the
cheap baseline comparison from the Laya reliability playbook.

Current evidence: 35 classifier tests pass on System One `2b8157a`; the ledger
has 31 human corrections, only four since the prior evaluation, and two own
sender preference rows. Backup `ledger.pre-proton-residency-v1.sqlite` under
`/var/lib/hwc/mail-classifier` restores with integrity_check=ok and matching
counts for all six tables. Premortem permits prerequisites and S1 shadow only.

Safety prerequisites are implemented in System One `c92d037`: 40 classifier
tests, the full npm build and test suite pass on its final merged commit.
Removing correspondent selection or the self-teaching guard fails its targeted
test. The Nix dispatcher check exercises the generated reopen wrapper and fails
with its reopen branch removed; dropping office from the identity defaults
fails the production Nix identity guard. Nix runtime activation is pending.
