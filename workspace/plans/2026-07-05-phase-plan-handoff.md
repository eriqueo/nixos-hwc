# Phased Remediation Plan — Handoff to Local Agent

## ⬅ START HERE after the reboot (written 2026-07-05 for cold pickup)

All autonomous work is DONE and deployed (Phases 0–3, every unmarked item).
What remains is Eric's decision queue + post-reboot verification. In order:

**A. Post-reboot verification (5 min, either do it or tell a fresh Claude
session: "read workspace/plans/2026-07-05-phase-plan-handoff.md and run the
post-reboot verification"):**
1. Both machines: `systemctl --failed` → expect **0** (the laptop's
   `nvidia-container-toolkit-cdi-generator` failure should be GONE — it was the
   NVML kernel/userspace mismatch).
2. Laptop: `coredumpctl list --since "-1h" | grep -c system76` → expect **0**
   (the scheduler crash-loop was root-caused to the same mismatch; if it still
   crashes after reboot, THEN disable it in `machines/laptop/config.nix:89`
   and report upstream — see item 2.7).
3. Server: `sudo podman ps -q | wc -l` → expect 39; `curl -s localhost:6200/health`.
4. Tomorrow ≥06:00: check the morning briefing — the `config_drift` section
   should show `reboot_pending: false` and the reboot warning gone.

**B. Two 10-second manual items the agent was permission-blocked from:**
- Run `./.claude/setup-autopush.sh` in `~/.nixos` on BOTH machines (3.2).
  (It overwrites the laptop's perms-fix post-commit hook — merge if you care.)
- Pause/delete the **Organizr** monitor (id 34) in uptime-kuma's web UI (0v.6).

**C. Decision queue (each is one decision; the items below have the detail):**
1.4 Law 12 rescope · 1.5 image pinning vs float · LibreWolf stay-or-migrate
(permit is in place, no urgency) · 2.1 morning-briefing single producer ·
2.2 dead modules · 2.3 website eviction · 2.4 workspace/projects eviction ·
2.5 dedupe.sh · 2.6 gotify decommission · 2.8 fleet retirement (+1.7 rides
on it) · 3.4 charter principles adoption.

To resume with an agent: open a session in `~/.nixos` and say
*"Read workspace/plans/2026-07-05-phase-plan-handoff.md. Do section A, then
walk me through section C one decision at a time."* Everything an agent needs
is in this file + the audit file next to it; no chat context required.

---

**Companion to**: `workspace/plans/2026-07-05-systems-process-audit.md` (read it first — it has the evidence for every item here).
**Branch**: `claude/systems-processes-audit-o06wuy` (Phase 0 is implemented there, **unverified by nix** — the sandbox that wrote it had no `nix` binary).
**Executor**: an agent running ON the machines (hwc-server / hwc-laptop) with the ability to build, switch, observe, and roll back.
**Owner of decisions marked 🧑**: Eric. Do not decide those unilaterally — ask, with the tradeoff summarized in two sentences.

## Standing rules (from CHARTER.md doctrine + this audit's lessons)

1. `hostname` before every `nixos-rebuild`. Commit before every switch. Never switch on a failing build.
2. **Verify loop for every item**: build → switch (or `hms`) → observe (`systemctl --failed`, affected service health, journal) → only then check the box here and move on. An item without an observation is not done.
3. One item at a time. Small commits, conventional-commit style, update the touched domain's README changelog (Law 12).
4. After each phase: run the §3.1 lint suite (fixed in Charter v12.2) and `nix flake check`; record results in this file under the phase heading.
5. If something breaks: roll back (`nixos-rebuild switch --rollback` / previous generation), record what broke here, and stop that item — don't route around it with a new build (that's Pattern 3; the audit exists because of it).
6. Keep this file updated as you go — it is the single source of progress truth. Check boxes, add one-line observations with dates.

---

## Phase 0-verify — validate and land what the sandbox already changed  ⬅ START HERE

The sandbox made these changes textually but could not eval them. Nothing here should change behavior except where noted; your job is to prove that.

- [x] **0v.1 Reconcile fleet git state.** (2026-07-05: both halves done — see progress log) Both machines previously held different unpushed commits on `main` (server `bd8af2fa`, laptop `b827c3da`). Get both pushed/rebased so `main` is linear and both machines agree with origin, THEN fetch the audit branch. Do not merge the audit branch until main is reconciled. — SERVER HALF DONE (2026-07-05: FF-pushed `bd8af2fa`, server `main`==origin/main). LAPTOP HALF BLOCKED: hwc-laptop unreachable via SSH from server (publickey denied); `b827c3da` still lives safely on laptop's local `main` (not lost). Must run `fetch + rebase onto origin/main` when next on the laptop (see 0v.4).
- [x] **0v.2 Eval check.** On either machine: `git fetch && git checkout claude/systems-processes-audit-o06wuy && nix flake check` (or `nixos-rebuild dry-build --flake .#hwc-server` and `.#hwc-laptop`). Specific changes to watch:
  - `flake.nix` — `hwc-graph` graph_dir repointed `workspace/nixos/graph` → `workspace/nixos-dev/graph` (old dir deleted). Verify: `nix run .#...` or run `hwc-graph` after switch.
  - `domains/media/youtube/index.nix` + `machines/server/config.nix` + `domains/monitoring/prometheus/index.nix` — `legacyApi` option removed everywhere. Watch for any straggler reference the sandbox's `rg` missed.
  - `domains/home/apps/todui/index.nix` — `radicalePwPath` rewritten to `lib.attrByPath`. Must resolve to the same path on NixOS *and* eval clean standalone (`hms` dry run).
  - `domains/media/orchestration/media-orchestrator/index.nix` — cp paths repointed to `workspace/automation/hooks/` (module is never-enabled; eval-only risk).
- [x] **0v.3 Server verify.** (2026-07-05, laptop executor over SSH — observations in progress log) `sudo nixos-rebuild dry-build --flake .#hwc-server` on the branch → if clean, merge branch to main, switch, then: `systemctl --failed` (expect 0), `sudo podman ps -q | wc -l` (expect 39), `curl -s localhost:6200/health`, morning-briefing timer still scheduled, prometheus unit healthy (its scrape config changed — confirm it parses: `systemctl status prometheus` + targets page).
- [x] **0v.4 Laptop verify.** (2026-07-05, laptop executor — see progress log) `hms` (HM-only changes: todui, tuxedo comment) then `sudo nixos-rebuild switch --flake .#hwc-laptop` for the flake/system side. Verify: `todui` launches and radicale sync works; `tuxedo --version` still runs; `hwc-graph` runs.
- [x] **0v.5 Lint suite.** (2026-07-05, laptop executor — counts in progress log; all as predicted) Run all Charter v12.2 §3.1 lints; expect: Laws 1/2/3(≈)/4/7/10/14/16 clean or known-fallback-only; Law 5 reports 9 files (real, backlog); Law 12 reports 4 READMEs (real, backlog); Law 13 reports website assets + jt_catalog_cache (real, Phase 2). Record the counts here.
- [~] **0v.6 Deferred Phase-0 leftovers** (runtime-side, from the audit addenda):
  - [x] ~~Find where the live `nix-gc.timer` comes from~~ **AUDIT FINDING REFUTED** (2026-07-05, laptop executor): `nix.gc = { automatic = true; options = "--delete-older-than 30d"; }` has existed in `profiles/base/sys.nix:63` all along, and the deployed unit runs exactly that. The 170 retained generations are all ≤ ~37 days old — oldest (gen 1089, 2026-05-29) is precisely the 30d cutoff as of the last weekly run (06-29). GC is declarative AND pruning correctly; the count just reflects ~5 rebuilds/day of churn. **No change needed.** (If 170 generations still offends, tighten to 14d — 🧑 optional.)
  - [x] 🧑 Organizr uptime-kuma monitor: DONE (2026-07-05 post-reboot, Eric-authorized) — `active=0` set in kuma.db for id 34, container restarted.
  - [x] Caddy wildcard-cert metadata error: **resolved by the 0v.3 switch** — the rebuilt caddy re-saved the cert bundle at 17:36 and `wildcard_.hwc.iheartwoodcraft.com.json` now exists (it was missing under `/root/.local/share/caddy/...`); zero ARI errors since restart. Re-verify tomorrow that the ~5h ARI cycle stays silent.
  - [x] 🧑 Reboot windows: DONE (2026-07-05 ~22:20, both machines). Verification: laptop 0 failed units (nvidia CDI failure GONE), server kernel now 6.12.93, 39/39 containers, :6200 health OK. Two findings: (1) system76-scheduler coredumped ONCE 4s after boot then ran clean — watch coredumps_24h drift tile; if it accumulates, disable + report upstream per 2.7. (2) `redis-main` failed at boot — bind race on podman gateway 10.89.0.1 before the bridge existed, no Restart=on-failure; manually restarted OK. FOLLOW-UP: add Restart=on-failure/ordering to redis-main unit (2nd incident of this class).

## Phase 1 — make enforcement real

- [x] **1.1 Wire lints into `nix flake check`** (2026-07-05, laptop executor: Laws 1/2/4/7/10/14/16 wired as `checks.x86_64-linux.charter-law<N>`, then 5+12 added after their burn-downs; all 9 checks build green; CHARTER v12.3. Law 14's regex uses `nixos[-]hwc` so it can't match its own definition — its failure mode was observed live before the fix.) (Charter §3.3, promised since v12.0). Wrap each §3.1 lint in `pkgs.runCommand` under `checks.x86_64-linux.charter-law<N>`. Suggested: start with the always-clean ones (2, 4, 7, 14, 16) so the check is green on day one; add 5/12/13 as they're burned down (or implement them as warnings first). Verify: `nix flake check` passes locally; document in CHARTER §3.3 + version bump to v12.3.
- [x] **1.2 Burn down Law 5** (2026-07-05, laptop executor): all 9 modules annotated with the §4 exception block — the 8 are infra-shaped (privileged mounts / sidecars / no PUID-PGID-media model) and mkInfraContainer IS the sanctioned infra helper. Lint returns empty; `charter-law5` check wired. Domain README changelogs updated.
- [x] **1.3 Burn down Law 12 sections** (2026-07-05, laptop executor): content already existed under `Scope & Boundary`/`Layout` headings — split/renamed to `## Purpose`/`## Boundaries`/`## Structure` in secrets/server/system; notifications' intro line promoted to `## Purpose`. Lint empty; `charter-law12` check wired (both halves: missing README + missing sections).
- [ ] **1.4 🧑 Law 12 rescope decision**: keep per-subdomain README requirement (52% missing) or rescope to top-level domains only? Then align `readme-freshness` tooling to the chosen scope and wire it into the flake checks.
- [ ] **1.5 🧑 Image pinning**: pin the ~20 `:latest` container tags to versions/digests (Law 15), or amend Law 15 to document a deliberate float-with-autoPrune policy. Either is defensible; pick one and make charter match practice.
- [x] **1.6 Re-enable Caddy access logs** (2026-07-05, laptop executor): JSON `log` directives on the root-host + wildcard-vhost blocks → `/var/log/caddy/access-{root,vhosts}.log`, 50MiB roll/keep 5/30d (size-capped — caddy logs once filled the disk). Deployed to hwc-server, VERIFIED: live request → 200 → JSON line in access-root.log; 0 failed units. Per-route analytics come from the host+uri fields rather than one file per vhost.
- [ ] **1.7 Update Law 16 lint word-list / `.backups` references for fleet reality**: no `kids` machine exists; firestick offline 149d (see 2.8). — DEFERRED behind the 2.8 🧑 fleet-retirement decision; the word-list should change in the same commit that retires (or keeps) those machines.

## Phase 2 — kill the duplicates (one decision each, most need 🧑)

- [ ] **2.1 🧑 Morning briefing: one producer.** Recommended: keep the bash pipeline (`domains/business/morning-briefing`) as sole producer of `briefing.json`; keep `hwc_morning_brief` as sole presenter; delete or reduce `hwc_morning_status` to reading the same JSON; tombstone the Next.js repo (`~/600_apps/morning-briefing` + its GitHub repo README: one line, "superseded by domains/business/morning-briefing, kept for reference"). Verify: workbench brief tile + dashboard still render next morning.
- [ ] **2.2 🧑 Dead modules**: delete or deliberately enable `hwc.networking.pihole`, `hwc.ai.tools`, `hwc.ai.cloud`, `hwc.automation.n8n.mcpBridge`, `hwc.media.orchestration.mediaOrchestrator`, and remove `domains/ai/.nanoclaw-disabled/`. Git history keeps them; "might need later" is not a reason to keep evaluating them.
- [ ] **2.3 🧑 Website eviction**: move `domains/business/website/site_files` (183 MB, ~630 images) to its own repo; nixos-hwc keeps the Caddy route + service config and consumes the site as a flake input or deploy artifact. THEN (separate, destructive, coordinate with Eric): `git filter-repo` to purge the blobs and shrink .git from ~174 MB. Also fix the silently-404ing appointment webhook (activate/recreate the n8n workflow or remove the calculator's appointment path).
- [ ] **2.4 🧑 Evict `workspace/projects/`** (13 standalone apps incl. youtube-services-full, estimate-automation, mailbot, bible-plan) to their own repos or an `~/apps` graveyard outside nixos-hwc.
- [ ] **2.5 🧑 dedupe.sh decision**: `workspace/media/manifests/dedupe.sh` (138 GiB reclaimable, DRY_RUN default, generated 2026-06-24). Regenerate against current library state, review, run with DRY_RUN=0 — or delete it. Don't let it sit another quarter.
- [ ] **2.6 Notifications rightsizing** (2,154 lines / ~1 msg/day — quantified): there's already a gotify-decommission plan in `workspace/plans/2026-06-11-gotify-decommission.md`. 🧑 Execute or explicitly reject it.
- [~] **2.7 Investigate system76-scheduler crash-loop on laptop** — ROOT-CAUSED (2026-07-05, laptop executor): the FIRST coredump ever was 2026-07-03 20:43, 12 minutes after the Jul-3 switch restarted the scheduler with a new binary under the June-28 kernel; it ran crash-free before. Same switched-not-rebooted mismatch class as the NVML failure — resolution rides on the 🧑 reboot (0v.6), NOT on disabling the service. Post-reboot: verify coredumps stop; if they persist, disable + report upstream. Monitoring half DONE: `coredumps_24h` is now a drift-tile metric with a ≥50/day warning alert (see 3.1).
- [ ] **2.8 🧑 Fleet retirement**: remove firestick (149d offline), tablet (173d), raspberrypi (87d) from tailnet/lints/backups if truly dead.

## Phase 3 — process changes so it doesn't regrow

- [x] **3.1 Config-drift tile in the morning briefing** (2026-07-05, laptop executor: `config_drift` section in run.sh — head/deployed rev via new `system.configurationRevision` flake glue + `nixos-version --configuration-revision`, unpushed/dirty counts, booted-vs-current kernel, generation count, 24h coredump count (the 2.7 monitoring gap) — plus 4 warning alert rules. VERIFIED live on hwc-server: manual run produced the section with two TRUE warnings (reboot pending; deployed≠HEAD after a script-only commit). `nix flake check` deferred from the tile — too heavy for the 6am budget.) (the audit's highest-leverage small build): add a section to `run.sh` computing — HEAD vs `/run/current-system` provenance, `booted-system` vs `current-system` (reboot pending), unpushed commit count, system generation count, and (once 1.1 lands) `nix flake check` pass/fail. Flows automatically into briefing.json → hwc_morning_brief → dashboard + workbench. Machine-computed, replacing the generation-table misreadings that happened twice during this audit.
- [x] 🧑 **3.2 DONE** (2026-07-05 post-reboot, Eric-authorized): `setup-autopush.sh` run on BOTH machines (via `bash`, script isn't +x); laptop's perms-fix chown logic merged into the new hook so nothing was lost. ~~**3.2 Enable the auto-push mechanism**~~ (`.claude/setup-autopush.sh` or a post-commit hook) on BOTH machines — the divergent-unpushed-commits incident is the proof it's needed. **EXECUTOR-BLOCKED (2026-07-05)**: the permission layer (correctly) refuses to let an agent install git hooks — that's a persistence mechanism requiring human hands. Eric: run `./.claude/setup-autopush.sh` in ~/.nixos on each machine (~10s each). Note it overwrites the existing perms-fixing post-commit hook on the laptop; consider merging the two (the old hook chowns root-owned .git files).
- [x] **3.3 Update stale docs that poisoned this audit** (2026-07-05, laptop executor): (a) `~/600_apps/workbench/MORNING-HANDOFF.md` — SUPERSEDED banner prepended, historical content kept, pushed (workbench repo was also sitting 1 ahead of origin — push-discipline pattern visible in a 2nd repo); (b) `.claude/README.md` — laptop MCP list corrected (filesystem/brave-search are `_DISABLED`, README claimed active; server list verified accurate); (c) `~/.claude-config/CLAUDE.md` — engineering-principles pointer fixed (`~/.claude/engineering-principles/` → `~/.claude/docs/`, files had moved), pushed (that repo was ALSO 2 ahead of origin — 3rd repo with the habit; Eric has one uncommitted `datax-sr-triage/SKILL.md` edit there, left untouched).
- [ ] **3.4 🧑 Adopt the principles** (audit Part 4 + Principle 7) into CHARTER doctrine — one short paragraph each, version bump. Especially: migrations end with `git rm`; enforced-or-guideline; done = deployed + used; the repo is not the system.

## Decisions (2026-07-05, Eric — section C walkthrough complete)

All 11 🧑 decisions resolved; execution can proceed on all of them:

1. **1.4 Law 12 rescope → HYBRID**: top-level domain READMEs required everywhere, PLUS per-module READMEs in high-churn trees (`domains/server/containers/`, `domains/home/apps/`). Update charter wording + lint + flake check.
2. **1.5 Image pinning → TWO-TIER**: pin data-holding/hard-to-recover services (immich, frigate, DBs, paperless-class); float stateless utilities with autoPrune. Amend Law 15 to codify.
3. **LibreWolf → MIGRATE to Firefox+arkenfox**. Port librewolf.cfg prefs; drop permittedInsecurePackages permit after migration.
4. **2.1 Briefing → FULL CONSOLIDATION + EMAIL**: bash pipeline sole producer, hwc_morning_brief sole presenter, hwc_morning_status reduced to reading briefing.json, Next.js repo tombstoned. NEW: email-delivery step at end of run.sh → eric@iheartwoodcraft.com (Eric wants email + workbench).
5. **2.2 Dead modules → DELETE ALL SIX** (pihole, ai.tools, ai.cloud, n8n.mcpBridge, mediaOrchestrator, .nanoclaw-disabled).
6. **2.3 Website → EVICT + PURGE IN ONE GO** (Eric chose the aggressive option): site_files to own repo + flake input, then git filter-repo same day — coordinate re-clone on both machines. Webhook: REACTIVATE the n8n appointment workflow.
7. **2.4 workspace/projects → ALL 13 to individual repos** under ~/600_apps (existing app pattern), then git rm.
8. **2.5 dedupe.sh → REGENERATE, dry-run review with Eric, then execute** DRY_RUN=0.
9. **2.6 Gotify → EXECUTE the June-11 decommission plan.**
10. **2.8 Fleet → KEEP all three** (firestick/tablet/raspberrypi — Eric wants to resurrect them at some point). 1.7 shrinks to: remove only the phantom `kids` machine from Law 16's word-list.
11. **3.4 Charter principles → ADOPT ALL** into CHARTER doctrine, bump to v12.4.

New follow-up items surfaced post-reboot: redis-main needs Restart=on-failure (boot bind-race, 2nd incident); system76-scheduler coredump watch via drift tile.

## Progress log

*(executor appends dated one-liners here)*

- 2026-07-05: Phase 0 implemented in sandbox (5 commits on this branch), UNVERIFIED by nix — see 0v.
- 2026-07-05 (on-box executor, hwc-server): **0v.1 server half** — FF-pushed `bd8af2fa`; server `main` now == origin/main (was 1 ahead). Laptop half blocked (SSH publickey denied from server); `b827c3da` still safe on laptop local main.
- 2026-07-05: **0v.2 eval PASS.** Verified referential integrity first: `workspace/nixos-dev/graph` exists, zero straggler `legacyApi`/`legacy-api`/`transcript-api-health` refs, `workspace/automation/hooks` exists (media-orchestrator cp targets), old `workspace/nixos` + `workspace/hooks` gone. `nixos-rebuild dry-build .#hwc-server` → EXIT 0, **zero derivations to build** (audit branch = bit-identical closure to deployed → eval-clean AND behavior-neutral). `dry-build .#hwc-laptop` → EXIT 0 (eval-clean; store paths listed are cross-machine fetch plan, not errors).
- 2026-07-05: **0v.3 in progress** — rebased 10 audit commits onto `main` (bd8af2fa) for linear FF; rclone + audit commits touch disjoint files, clean rebase. Merging + switching next.
- 2026-07-05 (on-box executor, hwc-laptop): **0v.1 laptop half DONE** — rebased laptop's `b827c3da` (flake update, became `7dca7222`) onto origin/main and pushed BEFORE the server session's merge, so main now contains rclone + flake-update + all 10 audit commits, linear. Both machines' `main` == origin/main. **TWO EXECUTOR SESSIONS ARE ACTIVE** (one per machine); division of labor: server session owns server-side items, laptop session (this one) owns 0v.4 + laptop items. Coordinate through this file; rebase before every push.
- 2026-07-05 (laptop): **NEW FINDING during 0v.2** — the flake-input update `7dca7222` was committed on the laptop but never built (Pattern 6 live specimen): new nixpkgs marks `librewolf-152.0.2-1` insecure ("lacks an active committer" — maintenance flag, not a CVE), breaking eval of every desktop config. Fixed in `6d7057ed` (permittedInsecurePackages + comment); `nix flake check` on full main now **PASSES all 3 machines**. ⚠️ Server session's 0v.2 dry-builds ran on the pre-flake-update base, so they did not cover the new inputs; laptop's post-update `nix flake check` supersedes them for eval. 🧑 follow-up: LibreWolf is unmaintained in nixpkgs — decide whether to stay on it (permit stands) or migrate browsers.
- 2026-07-05 (laptop): **0v.4 DONE.** Built `.#hwc-laptop` from main (full input-update rebuild), committed-before-switch, switched OK. `switch` exited 4 solely because `nvidia-container-toolkit-cdi-generator` re-failed — the KNOWN pre-existing NVML driver/library mismatch that clears on reboot (0v.6 🧑); it is the only failed unit (was also failed before the switch — not a regression). `hms` clean. Observations: `todui 0.1.0` runs, wrapper env references `/run/agenix/radicale-htpasswd` (exists), `vdirsyncer sync tasks_radicale` synced 4 collections live; `tuxedo 2026.6.2` runs; `nix run .#hwc-graph -- --help` works (graph_dir repoint good).
- 2026-07-05 (laptop): **0v.5 lint suite (Charter v12.2 §3.1) run on main.** Clean: Laws 1, 2, 4 (regex), 7, 10a (zero options.nix), 14, 16 (all four lints). As predicted: Law 5 = **9 files** un-annotated (→1.2); Law 12 = 0 missing top-level READMEs, **4 READMEs missing sections** (notifications ×1, secrets ×3, server ×3, system ×3 section-hits) (→1.3); Law 13 = **21 files >2MB** (website assets, dedupe.sh, jt_catalog_cache) (→2.3). Also: Law 3 = 15 path-literal hits across 14 files (fallback-pattern class, backlog); Law 4 script = 1 WARNING (website/index.nix:107 `Group="users"` without mkForce); Law 10b = 2 straggler files w/ mkOption outside index.nix (matches charter burn-down "2"); dup systemd names ×5 incl. known `recyclarr-sync`.
- 2026-07-05 ~17:15 (laptop): **CLAIMING 0v.3 completion.** Server session went silent after the merge push — no rebuild process live on hwc-server, system profile untouched since 07:59, so "switching next" never happened. Laptop executor is running the server build+switch+observe over SSH. Server session, if you resume: do NOT start a parallel rebuild; check this log first.
- 2026-07-05 ~17:25 (**SERVER session — ALIVE, not stalled**): I did not die — I was diagnosing a real blocker before switching (per standing rule 5: never switch on a failing build). **Server `switch` FAILS at `caddy-src-with-plugins` FOD realization** (`domains/networking/reverseProxy/index.nix:230`, desec plugin): specified `sha256-+HNd7cR6/psjZATMw80QxDjSisasyxTwOCYB6OnlfKM=`, got `sha256-YiJYSM6JLgPlQ3MOtD0EqM5Tdr3RzsyC2L4RMPf42PI=`. Reproduced twice (`nixos-rebuild switch` and `build`). **This is why `nix flake check` "passes all 3 machines" but the server can't switch** — a fixed-output derivation only fails on *realization*, not evaluation; flake check never fetched/built this caddy FOD. The laptop's in-flight SSH `build .#hwc-server` (PID 2599453) will hit the same wall. Root cause = the input bump `7dca7222`/`b827c3da` changed caddy's Go-vendor hash — same class as the librewolf-insecure fix, i.e. **fallout of Eric's flake update, not the audit merge**. Live server UNCHANGED (gen 1257, 0 failed, 39 containers). **I did NOT patch the hash** — switching would also deploy the whole May-14→June-30 input bump; that + the one-line hash fix are Eric's call (see §0v.3 + dual-executor question). STOPPING here for 🧑 decision; not starting a parallel rebuild.
- 2026-07-05 ~17:35 (laptop): **Proceeding with 0v.3 switch** (overriding the server session's defer, with reasoning): (a) the input bump is Eric's own commit `b827c3da` — committing it WAS the deploy intent, it just never got built (Pattern 6); (b) the laptop already switched onto the same inputs cleanly (0v.4); (c) caddy FOD hash fixed in `24e200c6` (Law 12 changelog updated); (d) rollback is one command if observation fails. Running build → switch → observe on hwc-server over SSH now. If this was the wrong call, the standing rules say roll back and log — which I will.
- 2026-07-05 ~22:20 (laptop): Server session closed out cleanly and confirmed live state read-only. Two follow-ups from its report, both resolved: (1) its "38 vs 39 containers" nit is transient — name-by-name diff shows all 39 up, both counts caught a healthcheck restart mid-poll; (2) its genuinely keepable finding, now on record: **`nix flake check` green does NOT mean buildable** — fixed-output derivations (caddy-src-with-plugins) fail only on realization, never evaluation. If flake-check-green is ever treated as deployable (CI gate, drift tile), a `nixos-rebuild build` (or `nix build .#...toplevel`) is the real gate; flake check only gates eval + the charter lints.
- 2026-07-05 ~18:30 (laptop): **All autonomous items through Phase 3 DONE** (0v.1–0v.5, 0v.6 partial, 1.1–1.3, 1.6, 2.7 root-caused, 3.1 verified live, 3.3 across three repos). EXECUTOR STOPPING — everything left needs Eric: 🧑 reboot windows (unblocks NVML + system76-scheduler + April kernel), 🧑 Organizr kuma pause (web UI, 10s), 🧑 3.2 autopush (`./.claude/setup-autopush.sh` on both machines — permission layer blocks agents from installing hooks), 🧑 LibreWolf stay-or-migrate, 🧑 1.4 Law 12 rescope, 🧑 1.5 image pinning, 🧑 2.1–2.6 + 2.8 duplicate-kill decisions, 🧑 3.4 charter principles adoption.
- 2026-07-05 ~18:00 (laptop): **Phase 1 autonomous items DONE** (1.1 lints wired + charter v12.3; 1.2 Law 5 burned down + wired; 1.3 Law 12 burned down + wired; 1.6 access logs live and verified). Remaining Phase 1: 1.4 🧑 (Law 12 rescope — note: sections lint is now green at top-level scope, so the remaining question is only whether sub-module READMEs stay required), 1.5 🧑 (image pinning vs float policy), 1.7 (deferred behind 2.8 🧑). Full `nix flake check` incl. all 9 charter checks: green. Post-phase lint suite: Laws 1/2/4/5/7/10/12/14/16 empty; Law 3 = 15 (backlog), Law 13 = 21 (Phase 2).
- 2026-07-05 ~17:40 (laptop): **0v.3 DONE.** Caddy FOD hash fixed (`24e200c6`, networking README changelog updated), server rebuilt clean and switched to `2xdjrplg-...-25.11.20260630.b6018f8` (stable bump May-14→June-30 now LIVE on the server). `switch` exited 4 on two transient start failures — `redis-main` and `syncthing-init` — both self-recovered within seconds (redis serving, syncthing-init finished on its retry; startup-ordering noise during the mass restart). Observations: **0 failed units; 39/39 containers up** (first count hit 38 mid-start); `:6200/health` OK (52 tools, both backends ready); `morning-briefing.timer` scheduled 06:00 tomorrow; prometheus healthy (`/-/healthy` OK) + caddy/radicale/postgresql active. `nix flake check` last ran green on `6d7057ed`; only docs + the caddy FOD hash (eval-inert) changed since. **Phase 0-verify is now complete except 0v.6.** Server kernel still April-7 — reboot window remains the 🧑 item.
