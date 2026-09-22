# mail/taxonomy

## Purpose

The canonical Nix registry for reviewed sender dispositions, optional factual
tags, and action subjects. System One publishes the pinned workflow-v2 contract
for State, Domain, and classifier traits.

Design: `docs/plans/unified-triage-architecture.md`.

## Boundaries

- **Is**: pure build-time DATA (`data.nix`) + pure derivation helpers
  (`lib.nix`). No options, no services, no index.nix — this is a library,
  not a module; both lanes import it directly so HM/system split-brain is
  structurally impossible.
- **Is not**: presentation (aerc maps palette roles→hex), model classification
  logic (System One owns that), or the mail-janitor's
  Gmail-side tiers (deliberately independent).
- **Custom aerc tags** (`aerc/parts/tags-custom.json`, `<Space>M` flow) stay
  OUTSIDE the taxonomy by design.

## Consumers (all build-time imports of `lib.nix`)

| Consumer | What it takes |
|---|---|
| `domains/mail/notmuch/index.nix` | exposes the legacy janitor deny list without applying local placement rules |
| `domains/mail/aerc/parts/tags.nix` | optional/manual tag presentation |
| `domains/system/mcp/index.nix` | pins the System One classifier contract directly |
| `domains/business/morning-briefing` | consumes the classifier's JSON snapshot; no prompt vocabulary |

## Editing rules

- **Teach the classifier**: use the aerc State or Domain correction keys. The
  v2 case ledger learns exact senders without a separate declarative writer.
- `data.nix` `senders.trash` is legacy input only for the separate Gmail
  janitor. It does not classify or place local mail.
- **Never** override `hwc.mail.notmuch.rules.*` directly in a profile or
  machine file — that silently re-forks the vocabulary.
- Changes deploy with the normal lanes: `hms` for rules/aerc, server
  `nixos-rebuild` (+ gateway `npm run build`, service restart) for the
  gateway JSON and the briefing prompt.

## Changelog

- 2026-09-21: Replaced the `urgent/review/noise` placement vocabulary with
  `act/look/bulk/junk` under `attention/`, matching the Laya classifier.

- 2026-09-22: Removed workflow state from this registry. The versioned System
  One contract now solely defines `state/*`, `domain/*`, and `trait/*`; this
  registry retains reviewed deterministic sender rules and optional facts.

- 2026-09-14: Added the temporary `queue` workflow marker that separates the
  managed decision queue from the legacy Inbox without abusing unread as state.
  Finance became classification-only so receipts remain visible for a decision.
- 2026-09-14: Learned two user-confirmed noise senders at exact-address scope:
  QuickBooks marketing and the Bozeman Daily Chronicle e-edition notice. The
  separate QuickBooks payment sender remains untouched.
- 2026-07-09: Created (Phase 1 of unified-triage). Data moved verbatim from
  `profiles/mail/home.nix` (trash/archive senders), `notmuch/index.nix`
  option defaults (newsletter/notification/finance/action),
  `aerc/parts/tags.nix` (categories/flags/groups), and
  `morning-briefing/prompts/mail-triage.txt` (known noise/review senders).
  Behavior-preserving: dispositions map to each sender's exact prior
  treatment; the only merge is trash/archive senders additionally appearing
  in the prompt's noise list.
