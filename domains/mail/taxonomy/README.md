# mail/taxonomy

## Purpose

The canonical Nix mail taxonomy for tag vocabulary, attention-state transport,
sender dispositions, and action subjects. System One separately publishes the
versioned model contract pinned by the flake.

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
| `domains/mail/notmuch/index.nix` | `derived.*Senders` / `actionSubjects` as the `rules.*` option defaults |
| `domains/mail/aerc/parts/tags.nix` | `data.categories/flags/groups` (adds theme colors) and `workflow.currentTag` |
| `domains/system/mcp/index.nix` | `jsonText` → store-path `mail-taxonomy.json` → `HWC_MAIL_TAXONOMY_FILE` → `mail.ts` |
| `domains/business/morning-briefing` | consumes the classifier's JSON snapshot; no prompt vocabulary |

## Editing rules

- **Add/teach a sender**: one entry in `data.nix` `senders.<disposition>`.
  Dispositions `trash|archive|newsletter|notification|finance` drive the
  existing on-arrival notmuch rules. Classifier learning remains exact-sender,
  review-first, and separate from those declarative rules.
- **Never** override `hwc.mail.notmuch.rules.*` directly in a profile or
  machine file — that silently re-forks the vocabulary.
- Changes deploy with the normal lanes: `hms` for rules/aerc, server
  `nixos-rebuild` (+ gateway `npm run build`, service restart) for the
  gateway JSON and the briefing prompt.

## Changelog

- 2026-09-21: Replaced the `urgent/review/noise` placement vocabulary with
  `act/look/bulk/junk` under `attention/`, matching the Laya classifier.

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
