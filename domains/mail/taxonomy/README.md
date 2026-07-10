# mail/taxonomy

## Purpose

The canonical mail taxonomy — single source of truth for tag vocabulary
(categories, flags), triage buckets, sender dispositions, and action
subjects. Kills the four-way drift that existed between the notmuch rules,
the aerc tag definitions, the MCP gateway's constants, and the mail-triage
prompt's hand-kept sender lists.

Design: `docs/plans/unified-triage-architecture.md`.

## Boundaries

- **Is**: pure build-time DATA (`data.nix`) + pure derivation helpers
  (`lib.nix`). No options, no services, no index.nix — this is a library,
  not a module; both lanes import it directly so HM/system split-brain is
  structurally impossible.
- **Is not**: presentation (aerc maps palette roles→hex), classification
  logic (rules.nix/afew and the LLM prompt own that), or the mail-janitor's
  Gmail-side tiers (deliberately independent).
- **Custom aerc tags** (`aerc/parts/tags-custom.json`, `<Space>M` flow) stay
  OUTSIDE the taxonomy by design.

## Consumers (all build-time imports of `lib.nix`)

| Consumer | What it takes |
|---|---|
| `domains/mail/notmuch/index.nix` | `derived.*Senders` / `actionSubjects` as the `rules.*` option defaults |
| `domains/mail/aerc/parts/tags.nix` | `data.categories/flags/groups` (adds theme colors) |
| `domains/system/mcp/index.nix` | `jsonText` → store-path `mail-taxonomy.json` → `HWC_MAIL_TAXONOMY_FILE` → `mail.ts` |
| `domains/business/morning-briefing/index.nix` | `promptFragment` → rendered into the triage prompt → `MAIL_PROMPT` |

## Editing rules

- **Add/teach a sender**: one entry in `data.nix` `senders.<disposition>`.
  Dispositions `trash|archive|newsletter|notification|finance` drive the
  on-arrival notmuch rules; `noise|review` are LLM-advisory only (prompt).
  Promoting a sender from `noise` to `trash` is a deliberate move between
  lists — never automatic.
- **Never** override `hwc.mail.notmuch.rules.*` directly in a profile or
  machine file — that silently re-forks the vocabulary.
- Changes deploy with the normal lanes: `hms` for rules/aerc, server
  `nixos-rebuild` (+ gateway `npm run build`, service restart) for the
  gateway JSON and the briefing prompt.

## Changelog

- 2026-07-09: Created (Phase 1 of unified-triage). Data moved verbatim from
  `profiles/mail/home.nix` (trash/archive senders), `notmuch/index.nix`
  option defaults (newsletter/notification/finance/action),
  `aerc/parts/tags.nix` (categories/flags/groups), and
  `morning-briefing/prompts/mail-triage.txt` (known noise/review senders).
  Behavior-preserving: dispositions map to each sender's exact prior
  treatment; the only merge is trash/archive senders additionally appearing
  in the prompt's noise list.
