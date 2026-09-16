# `docs/design/` — decided designs that later work is bound to

This directory holds **design decisions**: a document that audits the current
state, compares the options, and picks one, so that the implementation cards
which follow are mechanical rather than argumentative. A design doc here is read
by the person writing the diff, not by the person running the system.

It is a new directory as of 2026-09-16. Two existing siblings were considered
first and neither fits:

- `docs/plans/` holds *implementation plans* — a sequence of steps for work whose
  shape is already agreed (`plan-mkModule.md`, `unified-triage-architecture.md`).
  A plan assumes the decision; a design makes it.
- `docs/audits/` holds *point-in-time audits*: a snapshot of what is on disk plus
  a dry-run remediation script, per its own README. An audit describes state and
  never chooses between futures. The multiarch document contains an audit
  (`## Inventory`) but exists to close an option set, so filing it there would
  bury the decision inside a state report.

This satisfies Charter Law 12 (touched directory README updated alongside content
changes): the design directory owns its own README here.

## Structure

| Path                  | What                                                                                                                                                              |
|-----------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `multiarch-fleet.md`  | Audit of every `x86_64-linux` assumption in the flake (25 inventory rows with proven failure modes), the per-system output-shape options, and the chosen shape — Option A (`forAllSystems`) with an asymmetric `checks` split. Names the scope of the two follow-up cards and the ARM build-capability decision (2026-09-16). |

## Conventions

- One decision per document. The filename names the subject, not the date.
- Every claim about current behavior cites a `file:line` or quotes real command
  output. A verdict determined by reading is marked `(read)`; everything else is
  traceable to a command in the document's evidence section.
- The options section compares at least the realistic alternatives and closes with
  a comparison matrix, then picks exactly one.
- The recommendation states what is **out of scope**, so the follow-up work has a
  boundary it did not have to invent.
- A design doc is not amended after its follow-up cards land — the code becomes the
  truth. Supersede it with a new document and note the supersession here.

## Changelog

- 2026-09-16 — Directory created with `multiarch-fleet.md` (nightly-builds card
  01 of the multiarch-fleet goal). The audit proved four things that were
  previously assumed: the machine registry's per-machine architecture already
  works (`hwc-firestick` evaluates as `aarch64-linux`), the `claude-cowork`
  overlay is a genuine `eval-fails` because upstream publishes `x86_64-linux`
  only, the `codex` x86 pin is a `silently-degrades` rather than a hard failure
  because it carries no `meta.platforms`, and of the seven apps `profiles/base`
  enables only `herdr` is unavailable on aarch64. It also corrected the working
  check split: there are nine `charter-law*` lints (not eight), and
  `alert-tier-exclusivity` is source-pure rather than machine-bound.
