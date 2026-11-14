# Agent harness

## Purpose

The agent harness gives Claude Code, Codex, Pi, T3, and Herdr one static policy
source and one mutable state store.

## Boundaries

- Manages pinned agent instructions, skill discovery, provider adapters, state synchronization and the tracker service.
- Project repositories own their implementation and local instructions; project records own human decisions and continuation state.

## Structure

`sys.nix` receives Brain MCP URLs from the base role. It checks an explicitly supplied local-server URL when present, without reading networking or server namespaces.

The pinned handoff poll carries versioned handoff messages only. Old Close records retain history, late acknowledgements and safety holds, but grant no dispatch. Relays refuse unsupported messages before calling T3; canonical Review and Close use their reserved protocol.

The pinned tracker explains unsupported Close previews in plain words. The refusal keeps its error code and status, sends no Close request, and restores the button focus. Legacy error responses remain readable. Cleanup admission and authority are unchanged. Review and Close share one typed finding example; Close states the existing code/detail bounds. Strict result validation and the Review prompt are preserved.

The pinned `tracker/scratch.py` owns bounded manual and capability4 canonical scratch planning, cleanup and qualified archive expiry. Physical no-follow roots and anchored operations refuse unsafe trees. Private stages remain outside public archives; public markers bind the observed archive identity and metadata. Canonical body3 captures a sanitized summary and requires durable preparation, private removal and public archive facts. Unknown recovery observes only; it never repeats cleanup. Held evidence lists possible locations, not presence claims. Missing or changed proof holds expiry. Historical dated archives keep their reader until the tracked fleet drain.

Manual `ws close` and canonical Close use the shared whole-project observer before cleanup effects. A private scratch consumer holds cleanup even when checkout observations are clear. Unknown observations refuse; existing preservation and private-at-close/public-30-day policy remains. This is an as-of check, not containment against future writers.

The shared workspace inspector checks file-backed memory mappings as well as cwd, descriptors and arguments. It caps maps at 4 MiB per process and 32 MiB per scan; missing, unreadable, malformed or excess data holds cleanup as unknown. Mapping hits expose only PID and kind. This is a current-user, as-of observation, not a lock against later writers.

Close is enabled on hwc-work after36 installed capability4/body3 checks. Mixed Remove/Keep, stale preview refusal, private removal and public qualified archiving pass. One withheld archive ACK recovers through observation after exact helper shutdown; each effect occurs once. Capability1/2/3 histories retain captured readers, fingerprints and limits. Other hosts keep Close disabled.

The helper launches from captured `workspaceRoot`, above `projects/`. Its project-name argv no longer resolves into the protected project; the observer still checks external and ancestor processes without exemptions.

`tracker.lifecycle.close` defaults off and clears the relay runtime port while disabled. Its immutable runtime metadata captures the static revision, workspace/brain roots and explicit ordinary profile. The relay binds the installed ws path separately to avoid a derivation cycle. The ws runtime includes Bash/systemd; hub and relay restart on Close protocol changes. Canonical Close keeps pending evidence visible and accepts Closed only after the note, every authorized removed-or-kept disposition and both worker shutdown proofs. Keep needs a human reason and fresh matching physical identity, clean state, preservation and process checks. Unsupported lanes remain held.

A reserved Review must find its deterministic native thread absent in both detail and the command snapshot before taking a process baseline or reporting that no worker started. Existing or unknown identities stay held after an independent hub restore.

Workspace close verifies current remote heads after a successful bounded refresh. Automatic WorktreeRemove uses the same immutable process inspector through the installed `ws check-processes` command; it retains its separate local-branch preservation rule.

New Close requests keep a bounded, fingerprinted checkout inventory through cleanup. Review accepts only final native messages for the adopted turn, including recovered held results. Ordinary thread creation and delivery exclude its reserved provider.

`ws` checks current-user process references before checkout removal. Its immutable scanner uses existing noninteractive sudo authority to inspect protected process metadata; unavailable inspection refuses cleanup. It adds no sudoers grant.

`tracker.lifecycle` keeps new Review intake and dispatch separate and disabled by default. The hub and relay restart when their shared lifecycle protocol changes. Only a host advertising the exact tested native profile can receive a Review.

The tracker supports one bulk review for grouped project choices, with browser drafts and one reviewed submission.

The fleet control list names hwc-home, hwc-work and hwc-laptop.

- `index.nix` installs the pinned policy, state links, health CLI, the `ws` workspace allocator, the state-sync timer (which re-renders `LEDGER.md` after each run), the hourly `ws-audit` timer, and the opt-in `agent-cli-update` timer. Its `agentWorkspace` activation creates `workspaceRoot` (`~/800_agents`); `stateDir` is `~/800_agents/state`.
- `index.nix` builds `agentSkills` from the curated harness entries and registered `extraSkills`; `apps/rea` supplies its curated skill from the same pinned harness. `adoptedSkills` defaults to empty. The final output must pass the harness's `skill-curation-check` with its declared Python/YAML closure: the default has 23 global entries, and explicitly disabling the REA skill permits only that omission. Project packs stay outside global discovery. Name collisions and unapproved entries fail the build. `~/.claude/skills`, each `claudeConfigDirs` root and `~/.agents/skills` link to the result; Pi reads the same set. `agentSkillsMigrate` preserves old hand-installed directories before linking, leaving Codex's `.system` alone. The hourly drift timer checks the installed roots.
- `index.nix` installs `claimcheck` (the Artifact gate's verifier, from the pinned revision, with a `jsonschema` Python) and `guard-audit` (fire counts per blocking guard from `~/.local/state/agent-harness/guard-fires.tsv`; guards with no fire in 30 days are removal candidates).
- `sys.nix` adds the pinned revision's hermetic hook suites (`hooks/tests/run.sh`) to `system.checks`, so a failing guard fails the system build instead of reaching `/etc/agent-harness`. `agent-harness publish` also runs the live tier (`run.sh --live`) before it pins or activates anything.
- `sys.nix` installs machine-wide Claude policy under `/etc`, and generates Claude Code's MCP config as tmpfiles store symlinks: `~/.mcp.json` (`userMcp`, read by every project under the home directory: shared servers, `hwc-sys` over HTTP at `hwc.system.mcp.url`, `brain` at `userMcp.brainUrl`) and the nixos repo's `.mcp.json` (`projectMcp`: `git` plus per-host `extraServers`). The host running brain-mcp asserts `brainUrl` names its route. Every host asserts that no Syncthing folder overlaps `hwc.paths.user.agents`. It also owns `pipelineEnvironment`, the automation marker that headless-agent units merge.
- `contract.nix` defines the ownership and revision contract shared by both lanes. Its provider list comes from the harness `manifest.toml` `[programs]` (every entry with a `policyOwner`).
- `index.nix` renders the manifest's `[matrix]` and `[outside]` to JSON for the CLI (`AGENT_HARNESS_MATRIX`).
- `control.sh` implements local and fleet health checks plus policy publication. `agent-harness matrix [--fleet]` prints surface by agent program per host: each `provided` cell must have a probe and pass it; `missing` and `unsupported` show as declared. Skill fingerprints use fixed C collation so host locales cannot report false drift.
- `control.test.sh` checks split revisions, mutable runtime references, skill drift (hand install, foreign root, extra Pi path, drift alert retry), matrix cells (no probe, failing probe, undeclared state), unlisted outside skills, fleet names, and publication: `--plan` changes nothing, a refused verification keeps the pin off main, the pin goes verify -> push -> runner deploy, only named hosts activate (each through its own runner), an unreachable host is reported, and any `sudo`, `nixos-rebuild`, `home-manager` or toplevel build outside the runner fails it. The home verification owner runs it as `agent-harness-control`.
- `state-sync.sh` synchronizes only memories, the mistakes ledger, and final `ledger/*.json` and `guard/*.json` files, with one bounded validation case under `.git`. Each run commits local state, merges the hub, then validates; it pushes only valid state. Atomic writer temporary files remain local. It stages by contract glob (`projects/*/memory/**`), so a file an agent leaves beside a project's memory stays local and untracked.
- `state-validate.sh` owns the memory contract for both full-store scans and projected writes on stdin.
- `state-sync.test.sh` verifies import, links, validation blocking, recovery (including recovery from invalid state that came from the hub), commit, pull, and push against a throwaway hub. It also checks that a file outside the contract is never staged, that long frontmatter validates, and that an unreadable directory cannot hide a memory conflict.
- `state-validate.sh pre-receive` is the state hub's gate. On the host that sets `stateHub` (hwc-home), it is pinned as the hub's `pre-receive` hook through `hwc.home.core.repoHooks`. It accepts only `refs/heads/main`, checks each pushed tip out into a throwaway repo, and refuses any tip that fails validation or cannot be checked. Emergency bypass: `git -C <hub> config --unset core.hooksPath`; the next activation re-pins it.
- The pinned `tracker/` serves legacy cause/work inputs and per-problem explanation/action confirmations with Yes, No, Not sure and correction boxes. Its browser test exercises saving, reload, completeness and navigation on disposable project data.
- `tracker-handoff stamp <project>` (pinned `tracker/handoff_doc.py`) records the writer and each project checkout's HEAD in the project's live `handoff.md`; the hub (`TRACKER_LEDGERS`) compares them with every host's ws ledger and puts the handoff at the top of the next prompt.
- `tracker-link <project> --nonce N` (pinned `tracker/t3.py`) binds the calling T3 thread to a project, so "Done deciding" posts the next prompt into it. The hub only queues that ping; the `tracker-relay` user service on every host (pinned `tracker/relay.py`, `tracker.url`) polls for its own host's pings, posts them into the local T3 and reports back, so a thread on any host is reachable and no T3 credential leaves its host. The doctor fails while the relay is inactive. `tracker-wait <project>` (pinned `tracker/wait.py`) is the fallback outside T3: it blocks until the click, then prints the next prompt.
- Herdr App terminals (pinned `tracker/herdr.py`): run in a Herdr terminal, `tracker-link` links that terminal instead, and the relay types its pings there with `hc send` through an at-most-once delivery ledger. `tracker-open <project>` shows the project's labelled terminal or starts its agent in a new Herdr space with the next prompt. `tracker-open --machine <m>` starts it on a server's Herdr core and links it as that server's own terminal. `herdrEnv` points both wrappers and the relay at the managed `hc` where `apps/herdr-core` is on (the servers), else at `~/.local/bin/hc`; `herdr-app` is the unmanaged laptop trial; without a running core every Herdr path reports "not running" and T3 behavior is unchanged.
- Agents survive a reboot in Herdr terminals (pinned `tracker/herdr_restore.py`). The harness `herdr-session` hook labels an agent's terminal with its session (`agent.*`). The zsh init here runs `herdr-restore shell` at a Herdr terminal's first prompt and after a command that started an agent. When the recorded agent was lost with its shell, it resumes the session once in the same terminal, so address, labels and tracker link stay valid. When the agent ended while its shell lived, it forgets the record. `herdr-restore` lists recorded terminals here and on connected machines; `herdr-restore resume <t>|--all [--retry]` types `hwc_herdr_resume` into waiting ones.
- `index.nix` links the pinned delegate skill's Herdr templates (`skills/delegate/templates`: `reviewer`, `worker`, `codex-reviewer`, `codex-worker`) into `~/.config/herdr-core/templates/` on every host, one link per file. `hc run <template>` reads them on the host that runs the child. The delegate helper uses them when it is called from a Herdr terminal. A host without a core ignores them.
- `herdr-link` (pinned `tracker/herdr_link.py`, `tracker.herdrLinks`, laptop) is the `x-scheme-handler/herdr` desktop entry: `herdr://terminal/<machine>/<tN>` puts that terminal in the Herdr window (herdr.py `show`) and checks `herdr-app ls`; `herdr://project/[<machine>/]<id>` runs `tracker-open`. The `herdr-alerts` user service (pinned `tracker/herdr_alerts.py`, `tracker.herdrAlerts`, laptop/work/home) follows the local core's events over its socket, never starts a core, and sends one hwc-notify alert (topic `projects`) per blocked episode of an agent terminal on its own host; `done` is optional at priority 4. `notifyUrl` comes from `hwc.notifications.notify.url`, handed to the standalone lane by flake.nix.
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
static policy in the harness (`lifecycle/ws`, `guards/workspace-*.sh`); the design
is `~/000_inbox/downloads/agent/agent-workspace/design.md`.

New or changed memories declare `authority: observation|reference|decision` and
a non-empty `source:`, at the top level or directly under `metadata:` (where
Claude Code's memory writer moves them). Standing policy belongs in the static harness or a
project repository and is rejected from changed memory files.

The private `eriqueo/agent-harness` GitHub repository publishes static revisions
for both root evaluators. The server bare repository remains an authoring mirror.

## Operations

Run `agent-harness` for the interactive menu. Session launchers run the local
doctor automatically. `agent-harness doctor --fleet` compares every configured host with
the local desired revision. `agent-harness sync` validates and synchronizes mutable state.

`agent-harness publish` ships a harness revision. It runs the harness suites,
pushes the harness to `github` and `origin`, and prints its plan per host. When
the pin moves, it commits it on nixos-hwc `origin/main` in a detached
throwaway worktree under `~/.nixos-worktrees/` (detached, so the post-commit
hook pushes nothing), runs `release.py verify` on it,
and pushes it to `origin` main fast-forward only. A push that lost a race is
rebuilt from the new `origin/main`. This host then activates with `release.py
deploy --candidate <pin commit>`. A host already running the revision is left
alone. Nothing in publish runs `nixos-rebuild`, `sudo` or a bare merge of main.

- `agent-harness publish --plan` fetches remote refs and prints what would happen to each fleet host. It changes nothing else.
- `agent-harness publish` activates this host only. Other hosts keep their revision until asked; the final local doctor names them.
- `--host <name>` (repeatable) or `--fleet` also activates those hosts. Each runs its own runner over SSH (`release.py deploy --candidate origin/main` in its `~/.nixos`) after its harness checkout fast-forwards. An unreachable or refusing host is reported, and publish exits non-zero. `--fleet` ends with `doctor --fleet`.
- `--check` runs the preflight and prints the plan without pushing.
- `--candidate <nixos ref>` puts the pin on top of that nixos-hwc branch instead of `origin/main`, for a release that also carries nixos commits. The branch must contain `origin/main`; one that already pins the revision is used as is. Both reach `origin` main in the one verified push.

On a host with `cliUpdates.enable`, `agent-cli-update` runs daily. Run it by
hand with `systemctl --user start agent-cli-update`. Read the version changes
with `journalctl --user -u agent-cli-update`. To roll back a bad release, run
`npm install -g <package>@<previous version>` with the version from that log.

The doctor verifies actual provider paths, system and Home Manager ownership
manifests, state shape, Codex hook trust, commands, and the sync timer. It
checks that every skill root resolves to the shared set, that `~/.codex/skills`
holds nothing but `.system`, and that Pi's skill paths are the set; it prints a
content fingerprint, which `--fleet` compares across hosts (store paths differ
between nixpkgs versions). It fails on a skill a program loads from outside the
harness (Codex `.system`, enabled Claude plugins, claude.ai-synced plugins) that the
manifest's `[outside]` does not list, and on any matrix cell that fails. A skill
change updates the harness manifest's `[skills]` and its owning source; the package gate rejects unapproved additions. `npx skills add` and Codex's skill-installer cannot
write the read-only roots, and an install into `~/.codex/skills` is drift. A dirty
authoring checkout is a warning; a runtime reference to it is a failure.

## Changelog

- 2026-11-14 (d): `sys.nix` approves the generated MCP servers by name (`enabledMcpjsonServers` in the managed Claude settings, from the same attrsets as `~/.mcp.json` and the repo `.mcp.json`). Claude read `~/.mcp.json` as a project file in every new folder and asked "8 new MCP servers found", so an agent started by `tracker-open` or Workbench waited there silently. `agent-harness publish --candidate <ref>` pins on top of a nixos branch. `release.py` pushes `main` to `origin` fast-forward only after a successful activation (after the merge for `--action merge|build`), and fails loudly when origin moved; before, nothing pushed a fast-forwarded main.
- 2026-11-14 (c): Pins agent-harness bc48a94: `herdr-restore` lists a resumed Codex as running once it is in front (Codex records its session only at its first turn).
- 2026-11-14 (b): Pins agent-harness dd2ba71: the `herdr-session` hook, `herdr_restore.py`, the delegate Herdr transport and templates, `herdr_link.py` and `herdr_alerts.py` that the 2026-11-13 (e)–(g) entries need; `tracker-open` resumes a project's recorded agent in place.
- 2026-11-14: `herdrEnv` keeps `TRACKER_HC_BIN` on `~/.local/bin/hc` where `apps/herdr-core` runs the app's own binary (`serve.binary`, the laptop), not the Nix package.
- 2026-11-13 (g): Herdr links and alerts. `tracker.herdrLinks` installs `herdr-link` and its `x-scheme-handler/herdr` desktop entry; `tracker.herdrAlerts` runs the `herdr-alerts` user service (laptop, work, home). `tracker-open` and `herdr-link` share `trackerOpenEnv`. Needs the agent-harness pin that adds `tracker/herdr_link.py` and `tracker/herdr_alerts.py`.
- 2026-11-13 (f): Herdr templates for the delegate skill. `xdg.configFile."herdr-core/templates"` links the pinned harness `skills/delegate/templates` with one link per file. The links go on all three hosts, because a child terminal reads templates on the machine that runs it. They live here rather than in `apps/herdr-core`, which manages only the servers' core package; the laptop's core is the unmanaged app install. The harness owns the files, beside the helper that depends on their names.
- 2026-11-13 (e): Agents survive a reboot in Herdr terminals. New `herdr-restore` wrapper (pinned `tracker/herdr_restore.py`) and a zsh init block for Herdr terminals (`HC_TERMINAL_ID`). After a reboot, a kept terminal's recovered shell resumes the recorded agent session once at its first prompt; a failure is labelled `agent.restore=failed` and leaves the shell usable. Needs the harness pin that adds the `herdr-session` hook.
- 2026-11-13 (d): Pins agent-harness 924344a: `tracker-open --machine` for server Herdr cores; `tracker-open` recovers a project's terminal that is hidden, finished or duplicated instead of refusing; the relay never types into a terminal whose agent exited to a shell. `TRACKER_HC_BIN` follows `apps/herdr-core` when it is enabled.
- 2026-11-13 (c): `agent-harness publish` goes through the release gate. It used to build all three hosts (control.sh:447-456) and switch each with a direct `nixos-rebuild` (laptop:470, remote over SSH:472). It also fast-forwarded and committed on nixos-hwc main itself (:396, :437) and replayed a lost push with `pull --rebase` on main (:460). Because nixos-hwc's post-commit hook pushes the current branch, that pin commit on main also reached `origin` before any build. Now the pin is verified before it reaches `origin` main, each host activates through `release.py` on that host, and the default activates this host only (`--host`, `--fleet`, new `--plan`). The fleet-wide switch had no dependency behind it: each host's doctor compares that host's own system and user manifests, so a host on an older revision is consistent; `doctor --fleet` only reports the difference. The remote-store prebuild is gone, because each host's runner builds and verifies there. `control.test.sh` now fails on any activation outside the runner, and the home verification owner runs it (`agent-harness-control`).
- 2026-11-13 (b): Pins agent-harness a8fb5e5: tracked agent work in Herdr App terminals. New `tracker-open` wrapper (pinned `tracker/herdr.py`); `tracker-link` and `tracker-relay` get `herdrEnv` (`TRACKER_HC_BIN`, `TRACKER_HERDR_APP_BIN` under the home directory), `tracker-link` also gets `tracker.url`, and the relay restarts on `herdr.py` changes.
- 2026-11-13: Publish's one-time host migration is gone. Every host has moved to `~/800_agents/harness`, and no host keeps a `~/.claude-config` link. The commit gate no longer falls back to `bin/harness-policy-check`: every harness worktree carries `checks/`.
- 2026-11-12: The harness repo is `eriqueo/agent-harness` (flake input renamed; same revision and hash) and its working copy is `~/800_agents/harness` (`editableSource`, `control.sh` SOURCE, the ownership contract). Publish migrates a host the first time it reaches it: moves `~/.claude-config`, repairs its worktrees, leaves the old path as a link and renames both remotes (TEMPORARY until S6e). Managed Claude settings no longer rewrite the authoring path: the harness names `/etc/agent-harness/guards/` itself.

- 2026-11-12: Read the harness at its new homes (S6b batch 1): `lifecycle/tracker/` (hub, relay, `ws`, release checks, the Rust check), `guards/` (`log-mistake`, `guard-audit`), `checks/`, `rules/` (the Claude instruction links), `adapters/` (Claude agents and commands, Codex hooks, the Pi bridge), `packs/`. The two `[budget]` fallbacks are gone. Publish also skips an unreachable host, fast-forwards a behind nixos-hwc and replays a raced pin push.

- 2026-11-12: Codex and Pi get the harness commands (`~/.codex/prompts`, used as `/prompts:<name>`; `~/.pi/agent/prompts`) and the shared project memory (the harness `memory-recall` hook, run by the bridge). `agent-harness matrix` now probes `commands` and `memory` for both, and `mcp/codex` through `codex-mcp-sync --check`.
- 2026-11-11: `state-sync.sh link` relinks a memory link left from an older layout even when the store has no memory for that project yet, importing what it held. The first fleet `agent-harness matrix` found two such hwc-laptop links into `~/.claude-config/projects`.
- 2026-11-11: The harness `manifest.toml` replaces `skills/curation.json` and the provider list here. `contract.nix` reads `[programs]` (ownership JSON byte-identical before and after); new `agent-harness matrix`; the doctor checks matrix cells and `[outside]`. The principles hooks now carry the harness path in `settings.json`, so `sys.nix` drops its special-case rewrite.
- 2026-11-11: State sync stages only contract paths, and the validator no longer fails valid memories. hwc-work's sync was blocked from 2026-11-09 with 236 commits unpushed: `git add projects` had committed two closeout records that an agent left in `projects/domain-exposure-review/`. The records moved to that project's deliverables folder. Two validator faults came from `set -o pipefail`: `printf | rg -q` failed a valid memory when rg exited mid-write, and `find | rg -q` reported no memory conflict when one directory was unreadable. A blocked case is kept until the state changes, so one false failure held the sync.

- 2026-11-09: Bind fleet and local Brain MCP facts in the base role; preserve URL consistency checks without reverse domain reads.

- 2026-11-09 (c): `tracker.discordCards.summary` (on with the cards) sets `TRACKER_SUMMARY=1`: the `tracker-post-cards` call also keeps one standing message in `#projects` showing the top five of the hub's ranked list, edited in place. The hub keeps that message's id in `~/.local/state/hwc-tracker/summary.json`. Pins claude-config a3ed2f0 (ranked `/api/attention` with class, rank and key; `wait.need`; the summary).
- 2026-11-09 (b): `tracker.discordCards.publicUrl` gives card links the full tailnet host name (host name plus `hwc.networking.hosts.tailnetSuffix`). Discord refused the first live card because `http://hwc-work:8765` has no dot. Pins claude-config bfecf8a: the hub refuses to post with such a URL, and `POST /api/control/v1/posts/release` lets an operator re-post a card whose post did not land.
- 2026-11-09: Tracker decision cards reach Discord. New `tracker.discordCards` (enable, token file, bot ingress, start date) feeds `hwc-tracker` and the new one-minute `tracker-post-cards` user timer. Its one producer is the system control bot's `hwc.server.ai.hwcControlBot.targets.projects`: system Home Manager reads it through osConfig and `flake.nix` hands the standalone lane the same value. The hub bounds posting (3 sends a call, 30 a day, one message per card). Stop the timer to stop posting; disable the bot target to remove both sides.
- 2026-10-16: Pin tested legacy Close delivery retirement and the shared typed handoff parser. Preserve historical readers, late acknowledgements, occupied holds and canonical replay. Fleet enablement stays separate.

- 2026-10-16: Pin the shared typed finding example and explicit Close finding bounds after fresh-context tests and installed independent Review. Result schema, strict validation, Review prompt and cleanup authority stay unchanged.

- 2026-10-16: Pin tested unsupported-Close guidance after fresh-context resume and installed independent Review; preserve the existing cleanup limits and hwc-work-only enablement.

- 2026-10-16: Enable hwc-work capability4 scratch Close after36 installed native/helper checks and exact fixture retirement; preserve other hosts disabled.

- 2026-10-16: Pin the helper launch-directory correction and composed observer regressions; require a new installed acceptance before enabling Close.

- 2026-10-16: Pin capability4/body3 scratch summary, durable phase receipts and observation-only recovery; hold intake pending installed proof.

- 2026-10-16: Pin bounded manual scratch cleanup, postverified qualified public archives and matching expiry. Keep canonical capability3/body2 unchanged.

- 2026-10-16: Pin whole-project process checks for manual close, preserving private/public scratch when a consumer is active or inspection is unknown.

- 2026-10-16: Re-enable hwc-work Close after actual immutable mapped-writer and19 owning-hook checks; preserve all other hosts disabled.

- 2026-10-16: Pin bounded file-mapping process inspection and its actual worktree-removal regression; retain disabled Close until installed proof.

- 2026-10-16: Disable new Close while repairing a confirmed memory-mapping gap in current-user process inspection; preserve existing lifecycle readers and data.

- 2026-10-16: Enable completed-retention Close on hwc-work after26 actual installed native/helper checks, including kept identity/bytes and exact fixture retirement.

- 2026-10-16: Pin capability3/body2 bulk Close choices, prepared workspace identity and retained-checkout observations; keep intake disabled until installed mixed Remove/Keep proof.

- 2026-10-16: Enable the hwc-work schema2 Close lane after installed20-check two-checkout native/helper proof; other hosts stay disabled.

- 2026-10-16: Pin versioned multi-checkout Close0454772 with intake disabled until installed proof; retain exact schema1 readers and captured helper deadlines.

- 2026-10-16: Enable the tested hwc-work Close pilot after installed21-check ordinary Close and19-check Review proof; other hosts stay disabled.

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
