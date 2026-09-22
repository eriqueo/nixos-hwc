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

## Human controls

- aerc columns are `From | Subject | Date | Domain | State | Tags`.
- `<Space>ta`, `<Space>td`, `<Space>tl`, and `<Space>tj` teach
  `DO`, `DID`, `LOOK`, and `JUNK` through the ledger.
- `<Space>tc h|d|f|p|o` teaches Domain without changing state.
- `a` completes; `d` directly trashes without sender teaching.
- `J`/`K` marks plus `a`/`d` operate on the complete marked set, thread-wide.
- `<Space>tt` folds the selected thread; `<Space>tT` folds all threads.
- The sidebar contains workflow states only. Domain drill-down uses filters.

The morning briefing is a read-only view of the same v2 snapshot. MCP reflects
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
