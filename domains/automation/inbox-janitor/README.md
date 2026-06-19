# inbox-janitor — Inbox Downloads Drainer

## Purpose

Keeps `~/000_inbox/downloads` (the OS download target — `~/Downloads` is a symlink
into it, Syncthing-shared laptop↔server) from re-accumulating. On a timer it reads
the declarative rule table `~/000_inbox/_inbox-routing.yaml` and routes each **loose
file at the root of `downloads/`** to where it belongs:

- **datax** → stays resident in `downloads/datax/<class>/` (Eric's active work).
- **business / tech / personal** → drain to the home PARA dirs `~/100_hwc`,
  `~/300_tech`, `~/200_personal` under the matching numbered class folder.
- **secrets** (`env*`, `*.har`) → `downloads/_secrets/` (quarantine; never drained off-tailnet).
- **junk** (`.~lock.*`) → `downloads/_quarantine/`.
- **unmatched** → `downloads/_review/` (fail-loud; a human/LLM routes by hand).

Organized domain folders are never swept, so the pass is idempotent.

## Why server-only (single-writer)

`~/000_inbox` is a multi-writer Syncthing tree (laptop + server + LLM posts). Two
movers on two hosts would race the same path and Syncthing would emit
`.sync-conflict-*` copies — the exact failure that forced the brain vault onto a
single-writer hub. So exactly one host runs the drain. Enforced twice: the module
is only enabled on `hwc-server`, **and** `janitor.py` refuses `--apply` unless
`hostname == meta.owner_host` in the YAML (`--force` overrides, for manual runs).

## Structure

```
inbox-janitor/
├── index.nix    # Options + systemd oneshot service/timer (hwc.automation.inboxJanitor.*)
├── janitor.py   # The engine: pure classify() core + I/O edges; dry-run by default
└── README.md    # This file
```

The rule table itself (`_inbox-routing.yaml`) lives in `~/000_inbox`, not the repo —
it is live-editable config the janitor reads each run, so tweaking routing needs no
rebuild. Only changes to `janitor.py` or `index.nix` require a server rebuild.

## Enabling

```nix
# machines/server/config.nix
hwc.automation.inboxJanitor.enable = true;
# dryRun defaults true — watch `journalctl -u inbox-janitor`, then:
# hwc.automation.inboxJanitor.dryRun = false;
```

Manual dry-run anywhere: `inbox-janitor --config ~/000_inbox/_inbox-routing.yaml`

## Changelog
- 2026-06-18: Initial module. Timer (every 30 min) drains `downloads/` root per
  `_inbox-routing.yaml`. Ships with `dryRun=true`. v1 handles the downloads lane only;
  the YAML also specs naming-normalization for the `screenshots/`/`events/` lanes
  (events already normalized by hand) — a future pass folds those in.
