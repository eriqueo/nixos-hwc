# Mail Health Monitoring

## Purpose

Catch a mail outage before Eric notices a day of silence, without turning every
review item into an alarm. Every five minutes the local checks run and System
One's `health-cases` assesses them together with the sync status in one case
store. Alerts fire on transitions (open, escalate, close), never on repeats.

## Severity (Eric, 2026-10-12)

| outcome | means | examples |
|---|---|---|
| critical | mail is not arriving | fetch/index stale or missing; GPG, pass or Bridge failure open 30+ min |
| warning | a person should look, delivery still works | command backlog, label conflicts, a fresh failed attempt, stale inbox |

The unit's exit code means "did the checker run". A failed `mail-health.service`
is a broken checker. Health itself is in `summary.json`, the case store, the
alerts and the tracker card.

## What it checks

| lane | source | failure it catches |
|---|---|---|
| infrastructure | this script: GPG locks and agent, `pass`, Bridge service and IMAP/SMTP greetings, vault mode | the Mar 25 stale-lock cascade; Bridge down |
| freshness | this script: newest inbox file age | everything looks fine but nothing arrives |
| availability, commands, labels, residency | System One from `mail-sync/status.json` | stale fetch/index, pending commands, label conflicts |

Auto-remediation (default on) removes stale GPG locks, restarts gpg-agent and
restarts a stopped Bridge. Remediations are events, reported once to Slack, not cases.
Which GPG locks are stale is decided by `hwc-gpg-stale-lock` from the gpg app
(`domains/home/apps/gpg`); this script calls `--apply` (or `--check` with
remediation off) and reports its lines. Checked by `mail-health-gpg-lock`.

## Where it goes

| transition | channel |
|---|---|
| critical opened or escalated | n8n webhook (Slack) and hwc-notify priority 1 (Discord + email) |
| warning opened | n8n webhook |
| case closed | n8n webhook, `cleared:` |
| case open past `staleHours` | decision card `MH-*` on `tracker.project`; closes when the case clears |

Cards go through the tracker hub, never into `tracker.json`. Every run sends one
`hwc-tracker sync-health-cards <project>` carrying the complete set of cards
that should be open now, the empty set included. The hub adds missing cards,
closes open `MH-*` cards that are absent and reopens closed ones that are back.
A run the hub missed is repaired by the next run. The hub does not rewrite the
text of a card that already exists, so a card keeps the hours and the
open-since time it was created with, also after it reopens.

| `hwc-tracker` exit | this run | unit |
|---|---|---|
| 0 | `cards: N open on <project> (saved or unchanged)` | ok |
| 3 hub unreachable, 6 outcome unknown | one line in the journal; no file is written; the next run sends the full set | ok |
| 2, 4, 5, 7 (refused, conflict, incompatible) | one line; alerts and `summary.json` are still published | fails |

The command id is `mh-<first tried, ns>-<sha256 of the set>`, kept in
`tracker-command`. The same set keeps its id, so a repeat after an outage or an
unknown outcome is the same command. A changed set, or a set that returns
later, gets a new id: the hub conflicts on one id with two payloads, and it
answers a remembered id without reconciling again.

Limits set by the hub: 64 cards and 16 KiB for one command (about 20 cards of
this text), 200 bytes of title, 1000 of ask. A set past them is refused whole.

State: `~/.local/state/mail-health/{cases.sqlite,summary.json,infra-issues.json,last-healthy,tracker-command}`.
`hwc_mail health` (MCP) reads `summary.json`.

## Configuration

```nix
hwc.mail.health = {
  enable = true;
  webhook.url = "https://…/webhook/mail-health";   # machine one-off, Law 16
  tracker.project = "proton-mail";                  # one host only: one sender of the open set
  # tracker.client defaults to hwc.home.apps.agent-harness.tracker.package
  syncMaxAgeMin = 45;  freshnessHours = 6;
  escalateMin = 30;    staleHours = 24;
  autoRemediate = true; intervalMin = 5;
};
```

## Manual use

```bash
~/.local/bin/mail-health-check                     # run once, prints issues
jq . ~/.local/state/mail-health/summary.json
mail-classifier review-transport                   # the command backlog
mail-classifier withdraw-transport --command-id X  # drop a stale command
```

## Changelog

- 2026-11-13: Cards go to the tracker hub as one `hwc-tracker sync-health-cards` per run with the full open set. The job no longer reads or writes `tracker.json`, and no longer closes a card only in the run where its case closed. New `tracker.client`; the hub address is the agent-harness `tracker.url`. A refused sync fails the unit after the summary is published; an unreachable hub does not. Needs the Rust hub with writes on: the Python hub has no command route.
- 2026-11-10: `check_gpg` uses the shared `hwc-gpg-stale-lock` helper instead of its own test. The old test read the PID with `^\d+`, but GnuPG writes it right-aligned, so it saw every lock (live ones too) as stale and removed it. Requires `hwc.home.apps.gpg.enable`.
- 2026-10-12: One case store with System One (`--extra-issues`); severity by consequence; MH-* tracker cards for stale cases; exit code means the checker ran; `summary.json` for the MCP tool. Cooldown and first-failure files retired.
- 2026-03-26: Initial implementation
