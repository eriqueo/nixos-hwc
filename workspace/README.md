# HWC Workspace Directory

**Runtime-editable scripts and repo tooling.** Folders loosely mirror the
`domains/` hierarchy where a domain reference exists. Rule of thumb: if a
path in here is not referenced from a `.nix` file, a shell alias, or
CHARTER.md, it is a deletion candidate — the 2026-07-05 audit removed a
full layer of copy-not-move reorg debris on exactly that test.

---

## Structure

```
workspace/
├── ai/              # domains/ai/ — bible automation (canonical copy), AI docs
├── automation/      # domains/automation + media orchestration hooks (CANONICAL
│                    #   hooks dir — referenced by domains/media/orchestration/*)
├── home/            # domains/home — scraper (nix-wired), mail, photo-dedup
├── media/           # domains/media — youtube-services (nix-wired), beets helpers,
│                    #   manifests/ (generated reorg/dedupe scripts, see its README)
├── monitoring/      # operator health scripts (not Nix-wired); frigate-health.sh
│                    #   emits read-only camera/storage evidence for issue #100
├── nixos-dev/       # Repo dev tools: charter-lint, grebuild, add-home-app,
│                    #   graph/ (referenced by flake.nix hwc-graph), audits, lints,
│                    #   tests/ (executable regression suites for the tools here)
├── plans/           # Dated architecture proposals (CHARTER §6) + audit reports
├── projects/        # Standalone app code parked here — Phase-2 eviction candidates
│                    #   (each wants its own repo; see 2026-07-05 audit)
├── system/          # secret-manager.sh (`secret`; recipients from secrets.nix), secrets-parity,
│                    #   couchdb/zfs utilities, diagnostics/, setup/
│                    #   diagnostics/network/network/wifibrute.sh (scan + saved-report guidance), tests/
├── tools/           # readme-freshness.sh (Law-12 drift detector), web-speed.sh
└── utilities/       # lints/ (charter lints incl. permission-lint.sh — CHARTER §3.1),
                     #   audit/ (drift.py), setup-uptime-kuma.py
```

Load-bearing paths (verified 2026-07-05 — do not move without updating the
referencing site):

| Path | Referenced by |
|---|---|
| `nixos-dev/graph/` | `flake.nix` (hwc-graph package) |
| `nixos-dev/add-home-app.sh`, `nixos-dev/graph/hwc_graph.py` | `domains/home/core/shell/parts/zsh-init.nix` |
| `automation/hooks/*` | `domains/media/orchestration/{media-orchestrator,audiobook-copier}` |
| `home/scraper/*.py` | `domains/home/apps/scraper` |
| `media/youtube-services/` | `domains/media/youtube/parts/transcripts` |
| `tools/readme-freshness.sh` | `domains/automation/readme-freshness` |
| `system/secret-manager.sh` | `secret` alias (`domains/home/core/shell/parts/aliases.nix`) |
| `system/diagnostics/network/network/` | `net-tools` picker (`domains/home/core/shell/index.nix`); nine scripts share `network-report.sh` for explained output and outcome-based TLDRs |
| `utilities/lints/permission-lint.sh` | `CHARTER.md` §3.1 (Law 4) |
| `plans/` | `CHARTER.md` §6 (proposals convention) |

---

## Network diagnostic output

Run `net-tools` to choose a tool by purpose. Each tool explains what it checks,
what the result means, and what to inspect next. Each run ends with a TLDR:
an outcome, the findings behind it, the first next action and the limits.
Connection summaries distinguish configured DNS from public resolver answers.
Security summaries give incomplete stages priority and point to saved evidence.
Inventory summaries describe coverage rather than claim network health. Run `net-tools --details`
for full evidence; the default shows short excerpts with omitted-line counts.
Use Ctrl-Y in the picker to print the selected command. Add `--help` to that
command for a description without probes.

`system/diagnostics/network/network/network-report.sh` owns presentation,
result labels and DNS answer validation. It does not initiate probes.
`test-output.py` replays the nine scripts with fake commands, including empty
DNS answers, scan timeouts and security discovery. Run it with Python 3.
Saved capture and audit reports retain their existing locations and raw data.
The legacy `network-utils/network/wifibrute.sh` forwards to the active implementation; other old copies remain outside this picker.

`wifibrute.sh` fingerprints each host's recorded open TCP ports. Read
`tcp-inventory.tsv` for port ownership, coverage and source, and
`tcp-svcos-<host>.nmap` for service identification. `tcp-svcos.nmap` combines
the readable per-host reports. A host with a complete sweep and no open TCP
ports is skipped; missing or partial evidence remains untested.
After a host timeout, the script offers one top-100 TCP follow-up with a
120-second stage limit and a 30-second host limit. It preserves `tcp-all.*`
and keeps coverage partial even if the follow-up succeeds. A failed follow-up
keeps known ports and returns a nonzero audit result. Fingerprints share a
20-minute budget, with at most 120 seconds per host; remaining hosts are
untested when the budget ends. No intrusive or credential stage is repeated.
Run the CLI regression suite with Python 3. For the controlled loopback
fingerprint check, run:

```bash
WIFIBRUTE_LIVE_TEST=1 python3 workspace/system/diagnostics/network/network/tests/test_wifibrute.py AuditTests.test_live_loopback_fingerprinting
```

That check needs Nmap and noninteractive sudo; discovery and the other stages
use fixtures.

The default Wi-Fi audit output shows stage progress and five ranked concerns.
Each concern names the host/service, explains uncertainty, gives a next action,
and points to XML evidence. Duplicate findings merge by host, service and rule.
`REVIEW` means inspect a reported setting or login; `VERIFY` means confirm a
vulnerability lead. Coverage gaps remain visible. Unknown script output is
retained for manual review, so an empty concern list does not certify security.
The device table uses vendor and service hints; unidentified port names stay
unidentified instead of showing misleading port-table labels.

`summary.txt` contains the complete guidance. `findings.json` is a private,
replaceable version-1 interpretation of the XML and stage status. It omits
account names and passwords. Raw `.xml`, `.nmap` and `.log` files retain the
original evidence and may contain credentials. `--details` expands the guidance
and shows raw probe output during a scan. Normal output hides certificate
fingerprints, NULL compression, version-only CVE lists, guessed usernames and
RTSP path attempts. These remain distinct from real cipher findings, positive
script states and recorded logins. Runtime failures outside scan stages are
retained in `stages.tsv` as `audit-runtime` so report refresh preserves coverage.

Rebuild guidance from a saved run without probes, root access or network tools:

```bash
net-tools wifibrute report reports/20261008-134054.udOoJt
```

Use an absolute directory path when invoking `wifibrute.sh` from another folder.
This replaces only derived `summary.txt` and `findings.json`. Raw evidence stays
intact. The CLI suite covers positive findings, false alarms, credential
redaction, report regeneration, display limits and saved-report mode.

## Frigate field evidence

For the first post-change Frigate storage window, run on hwc-server after
2026-09-25 13:23 America/Denver:

```bash
bash workspace/monitoring/frigate-health.sh --since 2026-09-24T13:23:00-06:00 --hours 24
```

Run earlier to inspect a partial window (`window.complete` stays false).
The default without `--since` is the previous 24 hours, not a post-change claim.
The tool requires Python 3 and noninteractive sudo access to the Frigate
container. Exit zero means collection and current enabled-camera health passed;
it does not certify a full window or field coverage. Compare `present_samples`
and `online_samples` with `expected_samples` before comparing storage.
Missing samples and outages prevent a like-for-like comparison. Retention can
delete older footage, so collect the first-day result before three days pass.
Counts use retained database segments and event metadata; they do not prove
that a person walking every approach gets detected or notified.

## Changelog

- 2026-10-08: Replace wifibrute raw excerpts and keyword alarms with ranked XML
  findings, deduplication, guidance, coverage gaps and bounded device summaries.
  Add `report DIRECTORY` to reinterpret saved runs without probes; retain raw
  evidence and test positive/negative findings plus credential redaction.
- 2026-10-08: Fix issue #106: fingerprint discovered ports per host, record
  skipped/untested hosts, and offer one bounded follow-up for host timeouts.
  Preserve partial coverage and original reports. Add CLI regression cases
  and an opt-in controlled loopback fingerprint check.
- 2026-10-08: Add outcome-based TLDRs to the nine network tools, including early exits, DNS comparison gaps, weak signal, security leads and missing inventory tools. Preserve probe options and raw report formats; replay result branches with isolated commands.
- 2026-10-08: Explain checks and findings in the nine `net-tools` scripts, share terminal formatting, add full-evidence mode and isolated output tests. Correct false DNS success, timed-out public scan verdicts; preserve the new wifibrute discovery and stage tracking. Let bounded WiFi capture timeouts reach the summary.
- 2026-10-08: Repaired `wifibrute.sh` discovery parsing, CIDR and target handling;
  added `discover`, private report directories, bounded scans, stage status,
  opt-in credential/share checks, UDP SNMP, and privileged monitor cleanup.
  The legacy `network-utils` entry forwards to the active script. Regression
  tests: `python3 workspace/system/diagnostics/network/network/tests/test_wifibrute.py`.
- 2026-09-24: `secret-manager.sh` reads recipient rules from `secrets.nix`, so host enrollment also applies to interactive secret creation and edits. It fails before encryption if rules cannot be read or disagree.
- 2026-09-24: Repaired `monitoring/frigate-health.sh`: use the live API on port
  5000, omit raw logs and process arguments, return nonzero on collection/health
  failure, and emit JSON containing bounded recording/event totals and camera
  availability samples. No cron job, service restart, notification, or data write.
- 2026-09-23: `add-home-app.sh` v3.1 — no worktree diversion. Runs on `main`
  used to land in `~/.nixos-worktrees/<app>` on an `add-app/<app>` branch that
  nothing merged or activated (eden sat there uninstalled). The script now
  writes and commits in the current checkout, then activates Home Manager the
  way `hms` does — only when the module is committed, evaluates, and targets
  this host. `--no-switch` opts out; exit 6 = activation failed. Suite: 74
  assertions.
- 2026-09-22: Completed the `add-home-app.sh` v3.0 repair after the recovered
  nightly branch exposed three uncovered seams. Interactive `s` now re-enters
  search under `set -e`; machine enablement preserves both grouped and direct
  assignment shapes already used in `machines/*/home.nix`; and a failed
  integration restores every scoped file. The executable regression suite now
  carries 70 assertions, including both machine shapes and byte-identical
  rollback.
- 2026-09-15: `nixos-dev/add-home-app.sh` v3.0 — repaired against Charter v12.6.
  Four live breakages: machine detection walked every flake output via
  `nix flake show`; package search resolved against the moving `nixpkgs`
  registry instead of this repo's locked revision; `--no-interactive` set a flag
  nothing read, so every prompt still blocked; and generation emitted a Law-10
  `options.nix` and wrote to the deleted `profiles/home.nix`. Now: targeted
  `nix eval #nixosConfigurations --apply builtins.attrNames`, search and
  validation against the flake.lock nixpkgs, a real non-interactive contract
  (one exact top-level attribute or a loud failure with stable exit codes
  3/4/5), and generation through `domains/lib/mkSimpleApp.nix` or a Law-6
  native adapter plus per-app README, apps README index, and the enable in
  `machines/<machine>/home.nix`. On `main` it diverts to a dedicated worktree.
  New: `nixos-dev/tests/test-add-home-app.sh` regression suite driving
  the real script against isolated git + Nix fixtures.
- 2026-07-05: Audit cleanup (see `plans/2026-07-05-systems-process-audit.md`).
  Deleted reorg-debris duplicates: `hooks/` + `media/hooks/` (stale forks of
  `automation/hooks/`), `diagnostics/` + `setup/` (dups of `system/*`),
  `bible/` (subset of `ai/bible/`), `nixos/` (fork of `nixos-dev/`; flake
  graph ref repointed), 9 `utilities/*` scripts duplicated from `system/` and
  `nixos-dev/` (incl. the stale divergent `utilities/secret-manager.sh`),
  `claude_plans/` (session scratch), `prompts/`, `migrations/`. Added
  `media/manifests/` (generated ops scripts moved out of docs/). README
  rewritten to match reality (old version described a `business/` dir that
  didn't exist and omitted half the tree).
- 2026-06-12: Added `tools/readme-freshness.sh` — Law-12 drift detector.
- 2026-06-09: `secret-manager.sh` multi-recipient encryption; added
  `secrets-parity.sh`. See `domains/secrets/README.md`.
- 2026-03-25: Restructured to mirror domains/ hierarchy.
- 2025-12-10: Reorganized from arbitrary categories to purpose-driven structure.
