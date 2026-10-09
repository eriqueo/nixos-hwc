# Local mail workflow architecture

Status: workflow contract v3 remains active. The October 9 reliability repair
adds physical effect ownership and independent availability. Its seven-day soak
and compatibility retirement remain acceptance work; model State stays shadow.

## Mail sync reliability — approved October 9

Eric approved the rigorous repair in chat. The reproduced failure reserved an
effect before later preflight reads. A deadline left a zero-wire fixture uncertain,
and global recovery blocked unrelated commands. Aggregate core status then
misreported successful fetch/index as a mail outage. Two provider identities
sharing one Message-ID demonstrated why threading keys cannot authorize copies.

System One owns one bounded coordinator and one keyed physical effect lifecycle.
Nix owns credentials, paths, scheduling and activation. Each account fetches
independently and indexes before enrichment. Version-2 status publishes those
facts immediately. Labels, model availability and command review cannot replace
a successful fetch. MCP returns accepted command IDs and polls durable receipts.

Effects are keyed by account, provider identity, intent generation and operation.
Preflight validates exact identity, placement, stars and UIDVALIDITY before
reservation. Dispatch state commits before the wire call. Prepared or proven
no-dispatch effects can resume; dispatching, awaiting-readback and unknown effects
receive reads only. Exact postconditions establish verified completion. Original
uncertain receipts remain intact and conservatively quarantine their Message-ID
group when historical physical scope cannot be proved.

Proton dispositions use COPY of existing records. Managed labels share physical
identity leases. Real-folder EXPUNGE and mail recreation are outside this owner.
Afew membership moves and general Proton membership pushes are removed. Dedicated
Drafts/Sent channels retain their uploads; Gmail retains its provider behavior.
Archive/reopen and labels preserve stars. Trash permits Proton's complete native
star removal. Captured placement changes become conflicts rather than overwrites.
IMAP has no atomic compare-and-COPY across clients: phone edits between the final
preflight and COPY remain a provider concurrency limit, detected by readback.

The contract bounds accepted commands and active effects at 100, command identities
and label effects at 20 per run, and copies at eight per group. Accepted work is
retained at capacity. Durable cursors rotate work. Fetch has a 120-second ceiling
per account. Enrichment has a 120-second total budget with time reserved for labels.
Readback repeats at most six times with capped exponential delay and jitter;
wire mutations never retry from an uncertain receipt.

Health uses content-derived cases with state separate from outcome. It appends
judgments, emits alerts on transitions, and escalates pending commands at 30
minutes or stale fetch/index at 45 minutes. Its AUTO-MANAGED projection retains
30 days and at most 5,000 judgments; active cases are capped at 128. The effect
and human-event ledger remains CRITICAL and backed up.

Recovery uses `sync-mail core --effects-off`. Keep the current ledger. Code
rollback must retain effect containment; restoring an old database over newer
human events is not a recovery procedure. Historical uncertainty never becomes
retry authority merely because current placement matches its preimage.

Offline crash/collision/containment fixtures and disposable Bridge trials precede
activation. Live trials covered Archive, reopen, Trash, restore, stars, managed
labels, Drafts and Sent. Scheduled cycles and seven days without unexplained
reversal or unreported backlog are required before compatibility retirement.
Legacy direct-call regression helpers and v1 status readers are temporary;
remove them after that soak and measured consumer coverage. Migration completion
requires their deletion and the production wiring checks.

## Observable contract

Each managed thread has exactly one active workflow state and one Domain:

- State: `do | dont-know | did | look | junk`.
- Domain: `hwc | datax | family | personal | other`.
- `DO` means confirmed action. `DONT KNOW` means uncertainty for Eric to sort.
  Both stay in Inbox.
- `DID` means Eric acted and is waiting. Only a human may choose it; a new reply
  reopens the thread to `DONT KNOW`.
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
invalid, or failed inference uses visible `DONT KNOW`. Provider failure stays
retryable. Content-only State is shadow: a model guess cannot archive or trash mail. The model never assigns `DID` or completion.

The CRITICAL ledger under `/var/lib/hwc/mail-classifier` stores content-derived
thread cases, append-only judgments, append-only human events, independent
state/Domain locks, outcomes, and exact-sender learning. Its v1 database is
backed up before the schema-2 migration. The pinned model cache is REPLACEABLE.

Explicit routing rules use that same append-only event ledger; there is no
second aerc or arrival-hook rule store. A rule matches an exact sender plus a
required, case-insensitive subject substring and chooses `DO`, `LOOK`, or
`JUNK` plus one Domain. The most specific matching subject wins. A rule beats
model output and broad exact-sender learning, while a thread-specific human lock
and the new-reply Inbox safety rule remain stronger. Active rules are capped at
200. `JUNK` creation requires a separate confirmation.

## Human controls

- aerc columns are `From | Subject | Date | Domain | State | Tags`.
- `<Space>ms a|k|d|l|j` corrects State to DO, DONT KNOW, DID, LOOK or JUNK.
- `<Space>md h|d|f|p|o` corrects Domain without changing State.
- Routing review uses the shared command owner; the installed bindings define its keys.
- `a` completes; `d` directly trashes without sender teaching.
- `J`/`K` marks plus `a`/`d` operate on the complete marked set, thread-wide.
- `<Space>tt` folds the selected thread; `<Space>tT` folds all threads.
- The sidebar starts at DONT KNOW and includes the five States plus Bulk.
- Bulk is a read-only subset of uncertain newsletters or recurring unsubscribe mail.
  Security, finance, deadline and calendar facts exclude it. No folder move occurs.
- `<Space>gi` opens DO; `<Space>gk` opens DONT KNOW; `<Space>gb` opens Bulk.
  Domain drill-down uses filters.

The morning briefing is a read-only view of the same v2 snapshot. Routed items
carry a plain-language rule explanation, and the dashboard and email list active
rules. The Workbench mail digest consumes the same item summary. MCP reflects
live `state/*` tags and routes state/outcome writes through the same ledger as
aerc. Calendar mail creates private khal-format drafts for review and never
imports an event automatically.

## Failure and learning policy

Processing is bounded and repeats every 15 minutes. Provider failure leaves the
case visible and retryable. A human correction locks only the axis changed.
Exact-sender learning uses each thread's latest eligible human vote per axis.
At least three threads must support the winner, at least 80 percent must agree,
and latest feedback must agree. A new dissent suspends that axis. Corrections
still fix the selected thread in one step. Repeat clicks do not inflate support.
Legacy counters remain audit history, not authority; the event reader abstains
above 10,000 events per sender. DONT KNOW withdraws its thread's prior State vote.
`DID`, completion and stars are not generalized.
A new message changes
the thread fingerprint and reopens a prior `DID` or completed outcome to DONT KNOW.

Run v2 long enough to measure unsafe Junk attempts, fallback rate, correction
rate, and sender-learning precision before considering attachment reading,
automatic deletion, auto-unsubscribe, or a Jev comparison.

## Uncertainty migration and compatibility

The contract owns eight projected labels, including @do and @dont-know. Other has
no Domain label. A changed label vocabulary rebases the phone observer without
inferring a human edit. Phone correction application remains disabled.

The classifier ledger and cached report format stay schema 2. Reports expose
optional State vocabulary/display metadata; consumers treat absent old buckets as
empty. MCP validates either contract version 2 or 3 from the configured producer.
The model protocol and model labels remain unchanged.

`migrate-uncertainty` previews by default. Under the shared mail lock, it requires
an unlocked, unfinished DO case, matching automatic judgment and current thread
fingerprint. Explicit routing and human State provenance stay unchanged. Missing
history stays unchanged. `--apply` changes only the State tag and ledger State;
Domain, folders, stars and unread flags stay intact. A 1,000-case ceiling refuses
overflow before effects. Durable reservations precede idempotent tags, with
completion receipts for crash recovery. `--apply --rollback` restores matching,
still-unlocked migrated cases and preserves later human corrections. Ledger and
audit data are CRITICAL. Restore the backup in isolation before live migration.

## Proton two-way sync — refined plan, 2026-09-29

S0 is deployed at `20ea1240`, and Eric confirmed the two generated filters were
pasted. Their one-day delivery check remains open. Safety prerequisites and S1
shadow are live. Eric created all six S2 labels. The disposable test email was
sent, received and archived with All Mail and Sent preserved. The guarded probe
passed live after the COPY source repair. The bounded S2 projector is now
deployed and consumed on hwc-work, repaired at Nix `7b1f7e70` / System One `1096e14`.
S3–S4 are not implemented.
The corrected handoff contract is triage from both aerc and the Proton phone/web
app, using the same classifier ledger. This adds transport observation and
projection; it does not retune Laya or promote its shadow State model.

### Shape and authority

System One remains the sole owner of workflow State, Domain, human events and
sender learning. Add residency observation to its existing mail command and
ledger. The Nix mail-sync wrapper supplies transport readiness and invokes it
only after afew, mbsync and notmuch indexing succeed. Keep one sync lock.

Use read-only Bridge residency for the whole thread, including every physical copy.
The local Trash lane runs daily, so Maildir is an unsafe source for a ten-minute
observer. Read folder Message-ID headers with EXAMINE and BODY.PEEK, cap each
folder scan, and reject a scan if UIDs change before it ends. Credentials come
from the declared Proton account at command entry and never enter the ledger.
Body-free notmuch metadata supplies thread identity and message fingerprints.
Retain recent snapshot message IDs when a thread leaves the local index; remote
References/In-Reply-To linking an unseen reply suppress proposals until indexed.
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
   wire the observer after successful mail sync. Test fake read-only IMAP with
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
   COPY destinations and UID EXPUNGE are restricted to these label mailboxes.
   Bridge requires writable Archive selection for COPY; reject real-folder
   STORE/EXPUNGE and MOVE at the command boundary. First prove on
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

Initial planning evidence: 35 classifier tests passed on System One `2b8157a`; the ledger
has 31 human corrections, only four since the prior evaluation, and two own
sender preference rows. Backup `ledger.pre-proton-residency-v1.sqlite` under
`/var/lib/hwc/mail-classifier` restores with integrity_check=ok and matching
counts for all six tables. The updated premortem also permits S2 namespace
isolation and one guarded disposable-message probe.

Safety prerequisites are implemented in System One `c92d037`: 40 classifier
tests, the full npm build and test suite pass on its final merged commit.
Removing correspondent selection or the self-teaching guard fails its targeted
test. The Nix dispatcher check exercises the generated reopen wrapper and fails
with its reopen branch removed; dropping office from the identity defaults
fails the production Nix identity guard. Nix `9f244a81` is deployed: all checks
passed, the model service is active, nine own addresses are loaded and the two
historical self-preference rows remain stored but cannot affect predictions.

S1 is implemented in System One `3f18381`: 50 classifier tests and the full npm
build/test suite pass on that merged commit. Removing fingerprint gating or
the transition cap fails its targeted test. A read-only Bridge pilot on a
disposable ledger copy observed 1,578 recent threads in 7.11 seconds and
proposed zero baseline actions. Nix tests exercise the rendered sync script
with mover/sync/index/observer failures and reject removed observer wiring.
Late IMAP responses and missing UID validity fail closed. Final Nix checks and
live scheduled consumption passed in the deployment below.

S1 is deployed and consumed at Nix `6552346b`: all flake checks pass, including
failure injection and removed observer wiring. Transport renders match the live
files byte for byte. The first real core cycle observed 1,578 threads and zero
proposals; core and residency status are healthy. Human events remain 117 and
sender preferences remain 23. Ledger schema remains 2. Shadow began at
2026-09-29 16:14 MDT; its seven-day review is due October 6.

S2 first isolates the new label namespace from mbsync and legacy tagging, then
ships a guarded single-message probe. Eric created the six labels. The agent
sent the authorized disposable email with the contract's test subject, confirmed
delivery and archived only that message. SMTP and archive receipts use the same
content-derived key under `downloads/agent/proton-mail/`; neither effect retries
an unknown result. The probe refuses any other subject. Bulk projection implementation depends on whether Bridge COPY
preserves All Mail counts and label UID EXPUNGE preserves Archive. Reserve a
content-derived probe key before the first effect; a timeout is non-retriable
and requires inspection. No broad projector is activated from mocked evidence.
Before promoting live residency, also test that a slow model response cannot
overwrite a later phone action; re-read/CAS the case before its effects.

The remaining gates are tracked in [nixos-hwc #104](https://github.com/eriqueo/nixos-hwc/issues/104).
The guarded probe is installed; live preflight exposed cached pre-login
capabilities and stopped before any write. A trace with the deployed Python
proved authenticated CAPABILITY includes UIDPLUS; the probe now queries it
explicitly and decodes byte/text responses. The classifier suite runs in the
packaged-Python Nix check. The next live preflight found an unquoted `All Mail`
argument in the deployed client. No probe receipt or label write occurred.
System One `2ce31e2` quotes mailbox names through the existing transport helper
after checking the write allowlist. A strict mailbox fixture failed before the
repair; all 60 classifier tests, npm build and the full npm test suite now pass.
The quoting fix is deployed at Nix `f77d211f`. Its real COPY returned NO; Bridge
v3.24.2 logged "the mailbox is read-only". [Proton's COPY handler](https://github.com/ProtonMail/gluon/blob/master/internal/session/handle_copy.go)
rejects read-only sources. Read-only review found Archive UID 2912 and All Mail
UID 20152 intact, no @personal association, and unchanged cases, judgments,
human events and preferences. Keep failed receipt
`label-probe-2e068cae763842ad78461c04fc556db3`; it never retries.
System One `e7e3335` separates read, label-write and Archive COPY source selection.
It rechecks the exact source UID before COPY and rejects real-folder deletion
commands and wrong COPY destinations before I/O. All 63 classifier tests and
the full npm build/test suite pass. Removing command guards or COPY source
wiring fails its test. Nix `2fbc0a9a77b3f230391eb0e7a63aba94da8b4dbf` passed the
full flake check after merging the published branch history, then switched on
hwc-work. The fresh disposable probe verified adding and removing @personal:
receipt `label-probe-359d328f8848ffa3056773daee203fbc`, label UID 1 removed,
Archive UID 2913 and the single All Mail UID 20153 preserved. Read-only
inspection also confirmed neither original had a Deleted flag. Cases remain
586, judgments 950, human events 117 and sender preferences 23. The model
service is active; mail-sync status remains healthy. The prior failed receipt
is retained, with no automatic retry. Evidence covers one label round trip.
S2's bounded projector is next; S1 stays
shadow until the seven-day review, and S3 teaching retains its separate gates.
No agent review
follow-up is scheduled for the one-day filter check or the October 6 review.
The ten-minute shadow observer runs automatically. The original laptop handoff
could not be updated while that host was offline; this living plan is current.

### September 30 — legacy labels deleted early

Eric confirmed he removed every old Proton label. Current read-only Bridge LIST
contains only the six @ labels and the existing hide-my-email custom folder.
The interim `02-routing` filter still targeted 15 deleted labels. Its replacement
removes label-only rules and label actions while preserving each reviewed Seen,
Archive, spam guard and hide-my-email predicate. It assigns no @ labels: their
projection remains System One's responsibility. This does not promote S1, S3
teaching or complete S4 routing/view consolidation.

mbsync's core wildcard also excludes the entire contract `Labels/` namespace.
Its previous @-only exclusion still selected deleted legacy labels and produced
missing-mailbox warnings for retained nonempty local copies. Those local copies
remain intact; no mail or historical tags are deleted by this repair. The rendered
pattern check rejects old and @ label selection, keeps Inbox/Archive/custom-folder
selection and fails when the production exclusion is removed. A concurrent Gmail
timeout was also observed; it is separate from the label warnings.

Eric confirmed the repaired replacement is active in `02 - Routing`.
The installed `01 - Junk` is unchanged. Before this repair, a read-only audit
scanned 4,568 Trash copies and found no new protected Message-IDs compared with
the September 29 20:54 UTC baseline. Both fresh Trash deliveries matched reviewed
junk entries. There were 25 fresh Inbox and three fresh Archive deliveries, but
recipient-label acceptance was blocked by the missing labels. This was about
18 hours of observation, not full one-day acceptance. Receipt:
`/home/eric/000_inbox/downloads/agent/proton-mail/s0-day-one-audit.json`.

The deployed System One source matches the pinned `e7e3335` source byte for byte,
and its 63 classifier tests pass in this continuation. Human corrections and
outcomes remain 31/86 and sender preferences 23; scheduled classification has
advanced cases/judgments to 601/965. S1 remains shadow, with its October 6 review
still required. The latest observed snapshot contained 1,592 threads and zero
proposals; core, Trash and residency status lanes were healthy.

### September 30 — automatic label projection

System One `251050a` adds the bounded `project-labels` command. Each core sync
invokes it after transport, indexing and observation succeed under the same
lock. Its defaults limit a cycle to 100 label operations and 20 unresolved
receipts. It reserves content-derived write keys before IMAP effects and
acknowledges them only after checking remote labels, real-folder UIDs and stars.
After a crash it reads the postcondition before considering further writes;
unknown effects pause for review. Phone edits that differ from the acknowledged
labels are preserved as conflicts. The command never changes cases, judgments,
human corrections or sender preferences. S1 remains shadow and S3 teaching is off.

All 87 classifier tests and the full System One build/test suite pass on that
commit. Tests cover multi-copy mail, fresh replies, phone conflicts, a real
process crash, bounded work and guards against real-folder deletion. Removing
the CLI wiring or COPY guard makes the relevant test fail. A live read-only
preview against a temporary ledger copy found 482 possible label operations
and no label conflicts; it made no remote changes.

The notmuch hook also gives physical Proton Inbox residency priority over stale
transport tags. This prevents afew from reversing a fetched phone reopen on its
next run, while retaining the workflow decision and shadow observer. Nix checks
exercise the generated caller and three real notmuch/afew cycles; removing the
hook repair must reproduce the reversal. All Nix checks and system activation
passed at `1e30d58b`. The first bounded live write added `@family` to two physical
copies and preserved their Inbox and All Mail UIDs and stars. The subsequent
real core caller verified 10 more label associations, with zero conflicts or
pending receipts and 467 eligible associations deferred at the cycle deadline.
All 11 receipts preserved real-folder UIDs and stars. Human correction/outcome
counts remain 31/86 and sender preferences remain 23. Core, residency and labels
lanes are healthy; the ten-minute timer is active. Older eligible mail continues
in bounded cycles. DO/Other deliberately have no projected label; stale or
unclassified threads wait for classification.

The installed afew, notmuch and mbsync replay also preserves a reference-server
reopen across three full sync cycles. Live Proton phone reopen remains
unverified. Phone-label teaching remains off, unseen classifier accuracy remains
unmeasured and S1 review remains due October 6. Evidence:
`/home/eric/000_inbox/downloads/agent/proton-mail/verification/projection-live.json`
and `verification/reopen-repaired.json` in that same project directory.

### September 30 — label timeout and misleading outage alert

The initial writer reserved an intent before its second read-only preflight.
A normal deadline could then leave a requires-review receipt despite no remote
mutation. That stopped label backfill. Core transport remained healthy, but
mail-health treated the aggregate service exit as a critical mail outage.

System One `1096e14` finishes read-only preparation before reservation and defers
expired preparations without a receipt. Timeouts after effects still require
readback. Explicit `review-label-write` checks the unchanged remote preimage and
case before settling a pending receipt as not applied; it preserves its original
error and audit history. Fresh intents use the reviewed key as their predecessor.
The live review made zero remote mutations. The ledger was backed up first.

All 91 classifier tests, full System One build/tests and Nix checks pass.
Removing the preflight repair reproduces the failure. Nix `7b1f7e70` separates
label warnings from transport failures; core/Trash failures and stale transport
remain critical. The deployed decision function was exercised without sending
notifications. Two actual core cycles verified 9 and 8 label updates, with no
conflicts or unresolved writes. There are 52 verified applied receipts; all
preserve real-folder UIDs and stars. Human correction/outcome counts remain
31/86; sender preferences/corrections remain 23/21. All status lanes are healthy,
and the ten-minute timer is active. The second cycle deferred 429 associations.

Alert `72bbd8ce-ffa0-40ee-a1f8-0c2b88a146b9` had one successful SMTP delivery.
Read-only Bridge headers show its Sent and received Inbox copies with the same
Message-ID. They are preserved. Evidence:
`/home/eric/000_inbox/downloads/agent/proton-mail/verification/deadline-repair-live.json`.
S1 remains shadow until its October 6 review; phone-label teaching remains off.

### October 1 — repeated correction agreement

Eric approved the repeated-agreement rule in chat as the replacement for C3's
separate teaching step. System One `642d3c7` keeps aerc and MCP command shapes,
applies the thread correction immediately, and derives State/Domain preferences
independently from append-only lessons. Predecessor-linked correction events
retain changed feedback that returns to its earlier value. Exact retries add no
vote. Old preference rows and classifier schema 2 remain intact. The private
pre-policy backup restored with integrity `ok` and matching historical counts.

All 95 classifier tests and the full npm build/test suite pass on the final
System One commit. Disabling production preference consumption fails the runner
wiring test. Nix `631a040b` passed full flake checks and switched on hwc-work.
The installed classifier and contract match the tested source byte for byte;
all 95 tests passed again against that installed source. The real review command
consumed the new policy, and the model service is active. Fourteen MCP caller
tests pass. All 23 historical preference rows and 21 old correction rows remain
unchanged. No sender currently has enough independent lessons for an active
broad override. The model is unchanged. Phone learning is still off.

The fresh 24-thread review now has Eric's labels. Frozen content State scored
6/24 versus always-DO 7/24: one DO became LOOK and two wanted LOOK messages became
JUNK. Active embedding Domain scored 12/24 versus the prior-majority baseline
7/24 and Laya-only Domain 4/24. This small sender-separated diagnostic does not
support expanded State authority. No retuning or promotion occurred. Full
confusion matrices, frozen revisions and input-binding checks are in
`downloads/agent/proton-mail/verification/classifier-review-scored.json`; private
inputs, predictions and answers now live under the backed-up service evaluation
folder. New tuning requires a new frozen sender-separated holdout.

Both disposable phone archive actions produced completion proposals. After
explicit test-case preparation, both phone reopens produced reopen proposals
and survived three full core sync cycles, with one Inbox and one All Mail copy
each and no Archive/Trash/star copies. These are shadow observations, not live
completion application. Star/Trash tests and the October 6 review remain open.
