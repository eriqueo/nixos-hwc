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

Auto-remediation (default on) removes dead GPG locks, restarts gpg-agent and
restarts a stopped Bridge. Remediations are events, reported once to Slack, not cases.

## Where it goes

| transition | channel |
|---|---|
| critical opened or escalated | n8n webhook (Slack) and hwc-notify priority 1 (Discord + email) |
| warning opened | n8n webhook |
| case closed | n8n webhook, `cleared:` |
| case open past `staleHours` | decision card `MH-*` on `tracker.project`; closes when the case clears |

State: `~/.local/state/mail-health/{cases.sqlite,summary.json,infra-issues.json,last-healthy}`.
`hwc_mail health` (MCP) reads `summary.json`.

## Configuration

```nix
hwc.mail.health = {
  enable = true;
  webhook.url = "https://…/webhook/mail-health";   # machine one-off, Law 16
  tracker.project = "proton-mail";                  # one host only: the root syncs
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

- 2026-10-12: One case store with System One (`--extra-issues`); severity by consequence; MH-* tracker cards for stale cases; exit code means the checker ran; `summary.json` for the MCP tool. Cooldown and first-failure files retired.
- 2026-03-26: Initial implementation
