# Agent harness

## Purpose

The agent harness gives Claude Code, Codex, Pi, T3, and Herdr one static policy
source and one mutable state store.

## Boundaries

- Manages pinned agent instructions, skill discovery, provider adapters, state synchronization and the tracker service.
- Project repositories own their implementation and local instructions; project records own human decisions and continuation state.

## Structure

`tracker.lifecycle.close` defaults off and clears the relay runtime port while disabled. Its immutable runtime metadata captures the static revision, workspace/brain roots and explicit ordinary profile. The relay binds the installed ws path separately to avoid a derivation cycle. The ws runtime includes Bash/systemd; hub and relay restart on Close protocol changes. Canonical Close keeps pending evidence visible and accepts Closed only after the note, every supported removal and both worker shutdown proofs. Unsupported lanes remain held.

A reserved Review must find its deterministic native thread absent in both detail and the command snapshot before taking a process baseline or reporting that no worker started. Existing or unknown identities stay held after an independent hub restore.

Workspace close verifies current remote heads after a successful bounded refresh. Automatic WorktreeRemove uses the same immutable process inspector through the installed `ws check-processes` command; it retains its separate local-branch preservation rule.

New Close requests keep a bounded, fingerprinted checkout inventory through cleanup. Review accepts only final native messages for the adopted turn, including recovered held results. Ordinary thread creation and delivery exclude its reserved provider.

`ws` checks current-user process references before checkout removal. Its immutable scanner uses existing noninteractive sudo authority to inspect protected process metadata; unavailable inspection refuses cleanup. It adds no sudoers grant.

`tracker.lifecycle` keeps new Review intake and dispatch separate and disabled by default. The hub and relay restart when their shared lifecycle protocol changes. Only a host advertising the exact tested native profile can receive a Review.

The tracker supports one bulk review for grouped project choices, with browser drafts and one reviewed submission.

The fleet control list names hwc-home, hwc-work and hwc-laptop.

- `index.nix` installs the pinned policy, state links, health CLI, the `ws` workspace allocator, the state-sync timer (which re-renders `LEDGER.md` after each run), the hourly `ws-audit` timer, and the opt-in `agent-cli-update` timer. Its `agentWorkspace` activation creates `workspaceRoot` (`~/800_agents`); `stateDir` is `~/800_agents/state`.
- `index.nix` builds `agentSkills` from the curated harness entries and registered `extraSkills`; `apps/rea` supplies its curated skill from the same pinned harness. `adoptedSkills` defaults to empty. The final output must pass the harness's `skill-curation-check` with its declared Python/YAML closure: the default has 21 global entries, and explicitly disabling the REA skill permits only that omission. Project packs stay outside global discovery. Name collisions and unapproved entries fail the build. `~/.claude/skills`, each `claudeConfigDirs` root and `~/.agents/skills` link to the result; Pi reads the same set. `agentSkillsMigrate` preserves old hand-installed directories before linking, leaving Codex's `.system` alone. The hourly drift timer checks the installed roots.
- `index.nix` installs `claimcheck` (the Artifact gate's verifier, from the pinned revision, with a `jsonschema` Python) and `guard-audit` (fire counts per blocking guard from `~/.local/state/agent-harness/guard-fires.tsv`; guards with no fire in 30 days are removal candidates).
- `sys.nix` adds the pinned revision's hermetic hook suites (`hooks/tests/run.sh`) to `system.checks`, so a failing guard fails the system build instead of reaching `/etc/agent-harness`. `agent-harness publish` also runs the live tier (`run.sh --live`) before it switches any host.
- `sys.nix` installs machine-wide Claude policy under `/etc`, and generates Claude Code's MCP config as tmpfiles store symlinks: `~/.mcp.json` (`userMcp`, read by every project under the home directory: shared servers, `hwc-sys` over HTTP at `hwc.system.mcp.url`, `brain` at `userMcp.brainUrl`) and the nixos repo's `.mcp.json` (`projectMcp`: `git` plus per-host `extraServers`). The host running brain-mcp asserts `brainUrl` names its route. Every host asserts that no Syncthing folder overlaps `hwc.paths.user.agents`. It also owns `pipelineEnvironment`, the automation marker that headless-agent units merge.
- `contract.nix` defines the ownership and revision contract shared by both lanes.
- `control.sh` implements local and fleet health checks plus policy publication. Skill fingerprints use fixed C collation so host locales cannot report false drift.
- `control.test.sh` checks split revisions, mutable runtime references, skill drift (hand install, foreign root, extra Pi path, drift alert retry), fleet names, and publication to all hosts and source remotes.
- `state-sync.sh` synchronizes only memories, the mistakes ledger, and final `ledger/*.json` and `guard/*.json` files, with one bounded validation case under `.git`. Each run commits local state, merges the hub, then validates; it pushes only valid state. Atomic writer temporary files remain local.
- `state-validate.sh` owns the memory contract for both full-store scans and projected writes on stdin.
- `state-sync.test.sh` verifies import, links, validation blocking, recovery (including recovery from invalid state that came from the hub), commit, pull, and push against a throwaway hub.
- `state-validate.sh pre-receive` is the state hub's gate. On the host that sets `stateHub` (hwc-home), it is pinned as the hub's `pre-receive` hook through `hwc.home.core.repoHooks`. It accepts only `refs/heads/main`, checks each pushed tip out into a throwaway repo, and refuses any tip that fails validation or cannot be checked. Emergency bypass: `git -C <hub> config --unset core.hooksPath`; the next activation re-pins it.
- The pinned `tracker/` serves legacy cause/work inputs and per-problem explanation/action confirmations with Yes, No, Not sure and correction boxes. Its browser test exercises saving, reload, completeness and navigation on disposable project data.
- `tracker-handoff stamp <project>` (pinned `tracker/handoff_doc.py`) records the writer and each project checkout's HEAD in the project's live `handoff.md`; the hub (`TRACKER_LEDGERS`) compares them with every host's ws ledger and puts the handoff at the top of the next prompt.
- `tracker-link <project> --nonce N` (pinned `tracker/t3.py`) binds the calling T3 thread to a project, so "Done deciding" posts the next prompt into it. The hub only queues that ping; the `tracker-relay` user service on every host (pinned `tracker/relay.py`, `tracker.url`) polls for its own host's pings, posts them into the local T3 and reports back, so a thread on any host is reachable and no T3 credential leaves its host. The doctor fails while the relay is inactive. `tracker-wait <project>` (pinned `tracker/wait.py`) is the fallback outside T3: it blocks until the click, then prints the next prompt.
- The pinned `project-tracker` skill and generated phase prompt reserve cards for substantive choices. With no new cards, agents proceed to the next ready roadmap step in the same session. Brief clarifications use chat.

## State ownership

Nix pins static instructions, skills, hooks, and provider adapters. The Git clone
at `~/800_agents/state` holds
mutable memories, `MISTAKES.md`, each host's workspace ledger
(`ledger/<host>.json`, written only by that host) and the workspace guard's
`guard/arm.json` and `guard/budgets.json`. Project repositories still own their
local `AGENTS.md` or `CLAUDE.md` files.

The agent workspace (`~/800_agents`: `projects/`, `closed/`, `log/`,
`LEDGER.md`) is local to each host. Its allocator, guard and worktree hooks are
static policy in claude-config (`bin/ws`, `hooks/workspace-*.sh`); the design
is `~/000_inbox/downloads/agent/agent-workspace/design.md`.

New or changed memories declare `authority: observation|reference|decision` and
a non-empty `source:`, at the top level or directly under `metadata:` (where
Claude Code's memory writer moves them). Standing policy belongs in the static harness or a
project repository and is rejected from changed memory files.

The private `eriqueo/claude-config` GitHub repository publishes static revisions
for both root evaluators. The server bare repository remains an authoring mirror.

## Operations

Run `agent-harness` for the interactive menu. Session launchers run the local
doctor automatically. `agent-harness doctor --fleet` compares every configured host with
the local desired revision. `agent-harness publish` checks and pushes static
policy, updates the Nix pin, builds and switches the configured fleet, and finishes with
the fleet doctor. `agent-harness sync` validates and synchronizes mutable state.

On a host with `cliUpdates.enable`, `agent-cli-update` runs daily. Run it by
hand with `systemctl --user start agent-cli-update`. Read the version changes
with `journalctl --user -u agent-cli-update`. To roll back a bad release, run
`npm install -g <package>@<previous version>` with the version from that log.

The doctor verifies actual provider paths, system and Home Manager ownership
manifests, state shape, Codex hook trust, commands, and the sync timer. It
checks that every skill root resolves to the shared set, that `~/.codex/skills`
holds nothing but `.system`, and that Pi's skill paths are the set; it prints a
content fingerprint, which `--fleet` compares across hosts (store paths differ
between nixpkgs versions). A skill change updates the harness's curation inventory
and its owning source; the package gate rejects unapproved additions. `npx skills add` and Codex's skill-installer cannot
write the read-only roots, and an install into `~/.codex/skills` is drift. A dirty
authoring checkout is a warning; a runtime reference to it is a failure.

## Changelog

- 2026-10-16: Pin tested canonical Close source744485e with intake disabled; explicitly clear its runtime port while disabled.

- 2026-10-16: Declare default-disabled canonical Close runtime ports and dependencies; keep ordinary assessment separate from Review and include shared protocol restart triggers.

- 2026-10-16: Hold restored native identities before fresh Review baselines and early release; retain the original baseline for in-flight recovery.

- 2026-10-16: Require fresh remote preservation before workspace cleanup and apply the shared process check to automatic worktree removal. Missing or oversized observations retain the checkout.

- 2026-10-16: Pin final native Review result validation and stable captured Close inventory; ordinary thread selection excludes the reserved reviewer.

- 2026-10-16: Bind workspace removal to an immutable, caller-scoped process inspector and declare its Python runtime. Preserve all checkouts when inspection is busy, unavailable or exceeds its bounds.

- 2026-10-16: Wire separate Review intake/dispatch switches and shared-protocol restart triggers; enable the tested hwc-work lane only.

- 2026-10-16: Apply C5 skill discovery: no default upstream adoption, curated REA source, and a final assembled-output check with declared YAML support. Preserve explicit REA skill disablement and keep project packs outside global discovery.
- 2026-10-15: Add bulk question cards with per-item advice, editable choices, version and concurrent-answer checks, replay protection, and separate save/delivery status. Make grouped project decisions use this form by default as a workflow guideline.
- 2026-10-11: Hook suites gate the build. A live probe found guards that leaked (`git -C <dir> checkout -- f` on a dirty file), a suite that could not run, a staleness hook that had tested nothing since the 2026-10-01 state move, and an Artifact gate blocked on a missing `jsonschema`. `system.checks` now runs `hooks/tests/run.sh` on the pinned revision; `publish` runs the live tier; `claimcheck` and `guard-audit` install here. Pins claude-config with the fixes and the per-guard fire log.
- 2026-10-11: Two registration hooks so a Nix-built tool joins the harness without editing it: `extraSkills` (home lane, copied into `agentSkills` after harness and adopted skills, collisions fail) and `userMcp.extraServers` (system lane, merged into `~/.mcp.json` after the shared set). First producer: `apps/rea`.
- 2026-10-10 (c): `tracker-relay` restarts on `handoff_doc.py` changes too (relay.py imports it; it was missing from the triggers). Pins claude-config 837de39: the hub marks decided-but-unactioned cards as stalled, shows the newest brief date as "last work", and the python `-c` hook rule allows new-file writes.
- 2026-10-10 (b): `hwc-tracker` gets `TRACKER_WORKBENCH_AREAS_FILE` (the system `hwc.business.workbench.site` areas.json, read through osConfig; absent on hosts without the workbench) so the hub renders the Workbench area switcher in its rail. The page itself now uses the canonical `@scout/ui` shell (`/tokens/shell.css`, served live).
- 2026-10-10: The hub's Backlog tab reads the Refinery. New `tracker.refineryUrl` (loopback board, proxied with a 2 s timeout) and `tracker.refineryPublicUrl` (browser links and the add-to-backlog form) options feed `hwc-tracker` as `TRACKER_REFINERY_URL` / `TRACKER_REFINERY_PUBLIC_URL`. The Refinery stays the one store of work items; the hub also learns `stage` and question cards (claude-config `tracker/`).
- 2026-10-07: Stage final ledger and guard JSON files instead of whole folders. A held-open atomic-write fixture reproduced temporary-file publication before the fix and passes afterward.
- 2026-10-05: Fix locale-dependent skill fingerprints. A seeded C/English collation test with uppercase/lowercase names checks identical content gets the same fleet identity; reverting the sort locale makes it fail.
- 2026-10-01: Tracker pings reach any host. New `tracker-relay` user service on every host and `tracker.url` option; `hwc-tracker` drops its T3 environment and its `t3.py` restart trigger, since the hub no longer calls T3. Probed before rollout: hwc-laptop and hwc-home reach the hub (HTTP 200), and each host has T3's runtime file and CLI.
- 2026-10-01: The doctor checks Pi's hook bridge extension (`~/.pi/agent/extensions/hwc-hook-bridge.ts`, a store path) and fails on any bridge failure logged in the last hour (`~/.local/state/agent-harness/pi-bridge-failures.log`), so the hourly drift timer alerts on it.
- 2026-10-01: One skill set for every runtime on every host. `agentSkills` joins the harness skills with 13 adopted `cloudflare/skills` (new flake input); Claude, Codex (`~/.agents/skills`) and Pi read it. It replaces the Codex allowlists and the hand copies that had gone stale on hwc-laptop, and the `npx skills` installs on hwc-laptop and hwc-home. Only top-level dirs with `SKILL.md` count, so Claude Code's committed `skills/synced/` claude.ai copies no longer load as duplicates. Activation moves the old dirs to a backup. New `agent-harness drift` and hourly timer. `codex debug prompt-input` (0.159.3) listed all 49 skills plus 4 built-ins.
- 2026-10-01: Add protocol-4 training confirmation forms. Frozen explanations and actions use separate choices; whole-ticket completeness has its own question. Legacy inputs remain supported.
- 2026-10-01: Add `tracker-handoff` and give `hwc-tracker` the ledger path: the agent's live `handoff.md` heads the next prompt, with its coverage checked against each checkout's HEAD in the ws ledgers. The hub restarts when `handoff_doc.py` changes.
- 2026-10-01: Add `tracker-link` (pinned `tracker/t3.py`). An agent in T3 Code binds its own thread to a project; the hub's "Done deciding" button then posts the next prompt into that thread as a new turn through T3's `/api/orchestration/dispatch`, authorized by a 5-minute session the T3 CLI issues. `hwc-tracker` gets the node and T3 CLI paths. `tracker-wait` stays as the fallback outside T3.
- 2026-10-01: Agent workspace S8. `stateDir` defaults to `~/800_agents/state`, and the scripts, `contract.nix` and docs use it. Activation retargeted every memory link there and removed the S2 compatibility link on all three hosts; that one-time block is deleted again. The S2 move code is gone. A new hourly `ws-audit` user timer writes the ledger, renders `LEDGER.md`, expires `closed/` and logs findings.
- 2026-10-01: Continue down the roadmap when no new decision cards are needed. Wait for a decision only when remaining work depends on it.
- 2026-10-01: Add `tracker-wait`. The hub's "Done deciding — wake the agent" button stamps a handoff, and a waiting agent starts the next phase from it.
- 2026-10-01: Reserve tracker cards for substantive unresolved choices. The skill and generated prompt retain chat authorization, routine progress and explicit rejected decisions.
- 2026-10-01: Pin the tracker review form. It shows one ticket at a time, keeps drafts during ticket navigation and restores saved answers through the existing comment API. Plain decision cards and earlier comments remain supported.
- 2026-09-30: `tracker.enable` runs the project tracker hub (claude-config `tracker/server.py`) as the user service `hwc-tracker` on port 8765, enabled on hwc-work only. It restarts when the harness revision changes. `sys.nix` adds the read-only `pipelineEnvironment` (`HWC_PIPELINE=1`), the one producer of the marker that every headless-agent unit merges; `rg pipelineEnvironment domains` lists them.
- 2026-09-30: `agent-harness publish` ends with the fleet doctor from the newly installed CLI. Re-running its own pre-switch copy compared every freshly switched host with the old revision and reported false FAILs.
- 2026-09-30: `agent-harness publish` builds each remote host in its own store (`--eval-store auto --store ssh-ng://<host>`). Building hwc-home on hwc-work refetched its CUDA archives and a dropped NVIDIA download failed publication twice. `control.test.sh` checks the remote store flag.
- 2026-09-30: Agent workspace S2. Add `workspaceRoot` (from `hwc.paths.user.agents`), the one-time move of the state clone to `~/800_agents/state` behind a compatibility link at the old address, the `ws` package, a `LEDGER.md` render after each sync, and `ledger/*.json` and `guard/*.json` in the state contract (`contract.nix`, validator, fingerprint, staging; `state-sync.test.sh` covers them). `sys.nix` asserts no Syncthing folder overlaps the root.

- 2026-09-26: Rename the home fleet target to hwc-home; keep the shared harness pin and per-host session stores.

- 2026-09-25: Fleet health and publication include hwc-work. Publication builds
  and switches the configured host list instead of a separate two-host list.
- 2026-09-25: Publication updates the server's static-policy mirror before
  remote switches, then fast-forwards each host's authoring checkout. The
  publication test checks both remotes and all three build/switch targets.
- 2026-09-25: `.mcp.laptop.json`/`.mcp.server.json` were tracked (committed in
  2025, gitignored later), so the tmpfiles `r` rules that deleted them left
  every checkout dirty. They are now removed from the repo and the rules are
  gone. Their tracked contents were placeholders, never live keys.
- 2026-09-25: `state-validate.sh` accepts `authority`/`source`/`standing` as
  direct children of `metadata:`. Claude Code rewrites each newly written memory
  that way, so every new memory failed the store check and blocked sync (twice
  on 2026-09-25). `state-sync.test.sh` pins the accepted and rejected forms.
- 2026-09-25: `sys.nix` also generates `~/.mcp.json` (`userMcp`), replacing
  the HM shell module's copy on hwc-laptop and a hand-kept file on hwc-server.
  Both named brain on hwc-server, where it no longer runs since service-split
  wave 1; `brainUrl` now derives from the hosts registry (hwc-work), and hwc-work
  asserts it matches brain-mcp's route. The shared servers moved from the repo
  file to this one.
- 2026-09-25: `sys.nix` generates `~/.nixos/.mcp.json` (`projectMcp`), replacing
  the hand-kept `.mcp.laptop.json`/`.mcp.server.json` copies and their setup
  script. The server copy spawned a stale checkout build of the MCP gateway
  (dist/ from 2026-09-21) and held inline keys; the laptop copy had no gateway.
  Every host now reaches the Nix-built gateway service over HTTP, and the
  GitHub server reads its token from `gh auth token` at launch.
- 2026-09-24: Added opt-in `cliUpdates`: a daily user timer (04:30) that
  installs the npm-global `claude` and `codex` at `@latest` and logs each
  version change. It alerts through `hwc-notify` once on failure and once on
  recovery. It is on for hwc-server only, where nothing else updated them. On
  2026-09-24 claude 2.1.274 hid Opus 5.5 in T3, which needs 2.1.280.
  `bash` is on the unit's PATH because npm runs lifecycle scripts through `sh`.
- 2026-09-22: Unified store and pre-write memory validation behind
  `agent-state-validate memory-stdin`. Repeated invalid state now exits 75 from
  one fixed-size case projection without rerunning validation or touching the
  network; content changes retry, and only block/recovery transitions notify.
- 2026-09-17: Added the ownership manifest, changed-memory schema gate, fleet
  doctor, managed static-policy commit hook, and a publication command with a
  location-independent preflight and a Bash-owned final doctor handoff. The state service invokes its packaged
  validator directly so its minimal systemd `PATH` is sufficient. Sync failure
  and recovery alerts are emitted once per transition through `hwc-notify`.
- 2026-09-17: Added the shared control plane, separate mutable state sync,
  machine-wide Claude settings, provider health checks, and interactive CLI.
- 2026-09-17: Quoted interactive command assignments for shellcheck compliance.
- 2026-09-17: Replace stale memory symlinks during the state-store cutover.
- 2026-09-17: Publish static policy through private GitHub so both root evaluators can fetch it.
