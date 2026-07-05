# Systems & Process Audit — 2026-07-05

**Scope**: nixos-hwc, workbench, morning-briefing — the repos, the charter, the docs, and the *process* of building and maintaining them.
**Method**: five parallel deep audits (charter-lint compliance, docs/ inventory, workspace/ inventory, domains/ dead-code sweep, briefing-stack overlap) plus a process-layer review.
**Verdict in one line**: the architecture is genuinely good; the failure modes are all in *finishing* — migrations that copy instead of move, enforcement that was never wired up, and rebuilds that start before the last integration step of the previous build completes.

> **Updated 2026-07-05 with live verification results from hwc-server** (read-only run, 2026-07-04 evening). Corrections are applied inline; new live-only findings are in Part 5. Laptop-side items (workbench usage, tuxedo hash) are still pending a run on hwc-laptop.

---

## Part 1 — The five root patterns

Everything found below is an instance of one of these. Fix the patterns and the instances stop regenerating.

### Pattern 1: Migrations copy instead of move

Every reorganization in the repo's history left the old copy in place:

- `docs/archive/` is byte-identical to ~30+ files still sitting loose at `docs/` root — whole directories (`maintenance/`, `policies/`, `projects/`, `reports/`, `security/`, `analysis/`, `applications/`, `monitoring/`) were *copied* into archive, never removed from the source.
- `workspace/nixos/` vs `workspace/nixos-dev/` — the same toolset forked in place; `charter-lint.sh` now exists in **four** locations; the download hook `qbt-finished.sh` is byte-identical in **three**; `secret-manager.sh` has two *divergent* copies (one live, one stale — the dangerous kind).
- `workspace/diagnostics/` == `workspace/system/diagnostics/`; `setup/` == `system/setup/`; bible automation exists in three places.

The Charter's Doctrine §0.4 ("Migrations finish") already names this — but it's applied only to Nix code, not to files and docs. **A migration ends with `git rm`, or it didn't happen.**

### Pattern 2: Enforcement theater

The charter defines 16 laws with mechanical lints that "must return empty." In reality:

- **Two lints are silently broken**: Laws 5 and 12-sections use `rg -L`, which in ripgrep means `--follow` (symlinks), not `--files-without-match`. Both always print nothing → permanent false PASS. Hidden behind them: **9 container modules with no `HWC-EXCEPTION(Law 5)` annotation** and **4 domain READMEs missing required sections**.
- **Three lints can never return empty**: Law 2 fires on README changelog prose (5 hits, zero in code), Law 4 fires on mkContainer's own "not 1000!" warning comment, Law 16 fires on `profiles/README.md`'s forbidden-word list. A gate that is always red is the same as no gate.
- **§3.3 (`nix flake check` as enforcement) was never built.** `flake.nix` defines zero checks. Every lint depends on someone remembering to run it.
- Law 12's README contract is being lost to entropy: 53 of 102 directory modules (52%) have no README, and **every sampled domain README changelog is behind its code**.
- The charter's Law 10 burn-down list says "~21 stragglers"; actual count is **2**. The charter under-reports its own progress, too — drift cuts both ways.

**A rule that requires manual discipline decays into aspiration. Either a rule is enforced by a machine, or it's a guideline — the charter itself says this (Philosophy, line 6) and then doesn't follow through.**

### Pattern 3: Rebuild instead of finish (the "3/4-built" pattern)

The morning briefing is the type specimen. There are **five surfaces and three independent producers** of "show Eric his morning status":

| # | Thing | Where | State |
|---|---|---|---|
| 1 | Next.js dashboard | `~/morning-briefing` repo | Code-complete, polished, 3 LLM adapters — **never deployed, zero tests, one commit, abandoned** |
| 2 | bash pipeline | `domains/business/morning-briefing/run.sh` | **The deployed one** (6am timer). JobTread sections are hardcoded empty placeholders |
| 3 | `hwc_morning_status` MCP tool | `domains/system/mcp/.../morning-status.ts` | Working — re-implements #2's gather (services, df, notmuch, khal) in TypeScript |
| 4 | `hwc_morning_brief` MCP tool | `.../morning-brief.ts` | Working — presentation layer reading #2's `briefing.json` |
| 5 | workbench `brief` hub | `~/workbench/hubs/brief.toml` | Renders #4 — **but has never fetched a live tile; fixtures only** |

The history reads clearly: the Next.js app stalled (probably at deployment), so the bash pipeline was built as a workaround; the MCP path had a headless-permission issue, so `run.sh` re-implemented the gather in bash *"specifically because the MCP path fails under headless permission mode"* (its own comments). Each blocker was routed around with a fresh build instead of being fixed.

Workbench initially looked like the same signature from the other side — `MORNING-HANDOFF.md` states it has "never round-tripped one live MCP response or spawned one real zellij pane." **Live verification refuted this**: on the laptop, workbench is deployed via HM, aliased into the shell, had a zellij session alive for 1.5 days at check time, and its state file holds a calendar tile fetched live from the gateway on 2026-07-03. The last mile *was* finished — **the handoff doc is just stale**, which is its own lesson (Pattern 5): the audit inherited a false conclusion from the repo's own outdated documentation.

**The pattern: energy goes into greenfield architecture (fun) and stops at integration/deployment (unglamorous). "Done" needs to be redefined as *deployed and used*, not code-complete.**

### Pattern 4: Wrong repo boundaries

- `domains/business/website/` is **183 MB** — 872 files, ~630 images — an entire website plus its asset pipeline inside the NixOS config repo. It's why `.git` is 174 MB and it violates your own Law 13 (21 tracked files >2 MB). An 11.7 MB unsplash hero JPEG is configuration to nothing.
- `workspace/projects/` holds **13 standalone applications** (youtube-services at 70 files, estimate-automation at 37, mailbot, site-crawler…) — code with its own lifecycle, parked inside the config repo.
- Meanwhile `morning-briefing` — which *is* deployed from inside nixos-hwc — has a separate repo containing a *different, abandoned* implementation. The boundary is exactly inverted.
- The repo already has the correct precedent: **todui is an external flake input.** That's the model.

**Boundary rule: nixos-hwc holds configuration and thin glue. Anything with its own build/test/release lifecycle gets its own repo and enters as a flake input.**

### Pattern 5: AI exhaust committed as documentation

- `docs/` holds ~55 one-off AI-generated reports/plans (`AUDIT_INDEX.md` self-describes: "Auditor: Claude… Documents Generated: 5, Total Pages: ~270").
- `docs/audits/media/dedupe.sh` is a **4.7 MB, 60,233-line generated `rm` manifest** — 64% of the entire docs tree's bytes, and itself a Law 13 violation.
- `workspace/claude_plans/` holds 15 session dumps with names like `async-squishing-waffle.md`.
- `.script-inventory/` at repo root is a Dec-2025 generated snapshot of a directory tree (`workspace_fix/`) that no longer exists, with empty sidecar files.
- Governance docs rot alongside: `docs/DOCUMENTATION_STANDARDS.md` cites Charter **v6.0** (repo is on v12.1); `docs/README.md` describes 6 directories (there are 48).

**Policy needed: AI output is ephemeral by default. A report earns a commit only by being promoted into (merged into) a living doc. Living docs are edited in place; one living doc per topic.**

---

## Part 2 — Findings by area

### 2.1 Broken entry point (fixed in this commit)

Root `CLAUDE.md → AGENTS.md` was a **dangling symlink** (the file moved to `docs/AGENTS.md`), so every Claude Code session since the move has loaded no project instructions. Re-pointed to `docs/AGENTS.md`.

### 2.2 Charter lint scorecard (as of 2026-07-05)

- **PASS**: Law 7 (lane purity), Law 14 (flake self-ref), Law 10 structure (zero `options.nix` files), Law 16 (machine names / role imports / options in profiles).
- **FAIL, real**: Law 13 — 21 tracked files >2 MB (website images, dedupe.sh, a 2.2 MB checked-in JSON cache `estimator/scripts/jt_catalog_cache.json`). Law 5 (intended) — 9 raw-container modules lack exception annotations, incl. `mkInfraContainer.nix` itself. Law 12 (intended) — secrets/server/system/notifications READMEs missing required sections; 52% of sub-modules have no README at all.
- **FAIL, lint-bug (code is clean)**: Laws 1, 2, 4, 16-derivations — all fire on comments/prose/fallback patterns. One borderline real Law 3 hit: `domains/automation/refinery/index.nix:128` hard-defaults `/home/eric/700_datax/sr_gauntlet`.
- **Law 15 substance**: `podman.autoPrune` ✓, `SystemMaxUse` ✓, and `:latest` floating tags are the norm across ~20 container modules (charter says pinned). `nix.gc`: **corrected by live check** — a weekly `nix-gc.timer` IS active on the server, but nothing prunes old generations (no `--delete-older-than` anywhere in the repo): **169 system generations retained**, `/nix/store` at 77 GB.
- **Duplicate systemd services**: all benign merges except `recyclarr-sync`, genuinely split across `parts/config.nix:147` and `parts/setup.nix:8` — worth a look.

### 2.3 Dead and parked code in domains/

Verified never-enabled (defaults false, no assignment anywhere, not aggregator-enabled):

1. `hwc.ai.tools` (+ `.logging`) — AI CLI tools module, inert on all machines
2. `hwc.ai.cloud` (+ `.openai`, `.anthropic`) — cloud AI integration, inert
3. `hwc.automation.n8n.mcpBridge` — n8n MCP HTTP bridge, never enabled
4. `hwc.media.orchestration.mediaOrchestrator` — inert
5. `hwc.networking.pihole` — entire module, zero references from any machine

Plus deliberately parked: `hwc.ai.mcp` (mkForce false; superseded), beets/tdarr/organizr (enable=false), `youtube.legacyApi` (superseded), `.nanoclaw-disabled/`. The `ai` domain is ~⅓ dead weight.

Broken references: `domains/media/youtube/parts/legacy-api.nix` points at `workspace/media/youtube-services/transcript-formatter` — **does not exist** (real path: `workspace/projects/productivity/transcript-formatter`). todui READMEs reference deleted `workspace/home/tasq/`.

Live risks found on the way: ~~tuxedo placeholder hash~~ — **refuted by laptop check**: the module is the todo.txt TUI (not the hardware daemon), it's enabled in the desktop profile, builds, and runs v2026.6.2 — a `fetchurl` with a wrong hash can't build, so the sha256 is real and only the "PLACEHOLDER" *comment* is stale (delete the comment, `tuxedo/parts/package.nix:29`); the website's appointment-calculator webhook **404s live** (verified: `webhook/calculator-appointment` → 404; the sibling `webhook/calculator-lead` → 200 and works — one inactive n8n workflow, not a dead calculator). ~~recyclarr falls back to placeholder API keys~~ — **refuted by live check**: recyclarr synced clean the morning of verification, no placeholder/401/403 in 14 days of journal; the fallback code path exists but is not being hit.

### 2.4 Complexity outliers (overengineering candidates)

| Area | Size | Question to ask |
|---|---|---|
| `notifications/` | 2,154 lines | Hexagonal dispatcher + gotify + igotify + bridge — to send yourself notifications. Could one dispatcher + one channel do it? (A gotify-decommission plan already exists in workspace/plans.) |
| `mail/` | 46 files | Every component split into parts/. Fragmentation cost now exceeds navigation benefit. |
| `paths/paths.nix` | 640 lines, 1 file | The opposite drift — the only monolith in the repo. |
| Law 12 as written | per-subdomain READMEs, 4 sections + changelog | 52% missing proves the contract exceeds manual capacity. Reduce scope (top-level domains only) or automate — don't keep a law that's half-false. |
| workbench | full hexagonal core, 2 shells, 18 test files | ~~"hasn't fetched a live tile"~~ — refuted: in active daily use on the laptop (live session, real tile fetches). The remaining question is only whether the architecture is heavier than a personal tool needs, and that's a judgment call, not a defect. |

### 2.5 Pattern drift in domains/

- **media**: container defined in `sys.nix` for ~8 services, in `parts/config.nix` for ~9 others; naming mixes bare (`sonarr`), `-container` (`immich-container`), `-native` (`jellyfin-native`) with no rule.
- **business**: every service is a different paradigm — nix-built derivation (leads), Vite build from `./.` (estimator), shell-script oneshot (morning-briefing), mkContainer (firefly, paperless).
- The helpers (`mkContainer`) are consistently used — only file layout drifted. One documented "this is the shape of a service module" example, enforced by lint, ends the drift.

### 2.6 Repo hygiene (root)

Tracked at root and should not be: `.backups/` (old machine snapshots), `.cache/nix/fetcher-cache-v4.sqlite` (a SQLite cache in git), `.lint-reports/` (Sept-2025 outputs), `.script-inventory/` (stale generated snapshot), `.wrangler/cache/`, `meta/GEMINI.md` (0 bytes) + stale Gemini-era agent files.

---

## Part 3 — Prioritized plan

### Phase 0 — Mechanical deletions and lint fixes (~2 hours, no design decisions)

1. ~~Fix `CLAUDE.md` symlink~~ (done in this commit).
2. Fix the charter lints (bump charter to v12.2):
   - Laws 5 & 12: `rg -L` → `rg --files-without-match`.
   - Law 2: add `--type nix` (stop firing on README prose).
   - Law 4: anchor the regex to values, e.g. `rg 'PGID\s*=\s*"?1000"?\s*;'`.
   - Law 16: add `--glob '!README.md'` to the derivations lint.
   - Update Law 10 burn-down text (~21 → 2).
3. Delete tracked cruft: `.backups/`, `.cache/`, `.lint-reports/`, `.script-inventory/`, `.wrangler/`, `meta/GEMINI.md`; add to `.gitignore`.
4. docs/: delete every loose top-level file that is byte-identical to its `docs/archive/` copy (~30 files); collapse `archive/standards/standards/` and the duplicate charter-versions set; move the 6 generated `.sh` scripts and 4 n8n `.json` files out of docs (delete or `workspace/`); delete or rewrite `DOCUMENTATION_STANDARDS.md` (v6.0-stale) as a 10-line pointer; rewrite `docs/README.md` to match reality.
5. workspace/: delete verified duplicates — top-level `hooks/`, `media/hooks/`, `diagnostics/`, `setup/`, `bible/` + `projects/bible-plan/` (keep `ai/bible` or archive all), `utilities/` dups of nixos-dev files, stale `utilities/secret-manager.sh`, `claude_plans/`, `prompts/`, `migrations/`.
6. Repoint `flake.nix:401` from `workspace/nixos/graph` → `workspace/nixos-dev/graph`, then delete `workspace/nixos/`.
7. Fix or delete `legacy-api.nix` (dead path); it's already superseded.

### Phase 1 — Make enforcement real (this is the highest-leverage structural fix)

8. Wire the (now-fixed) lints into `checks.x86_64-linux.charter-law<N>` in flake.nix so `nix flake check` is the gate — charter §3.3, promised, never built. Until a law is wired, demote it to a guideline in the charter. This single change converts the charter from aspiration to mechanism.
9. Add generation pruning to the existing GC (`nix.gc.options = "--delete-older-than 30d"` or equivalent — 169 generations are currently retained). Pin the ~20 `:latest` image tags, or amend Law 15 to say what you actually practice.
10. Law 12 rescope: require READMEs at top-level domains only; sub-module READMEs optional. `workspace/tools/readme-freshness.sh` + `domains/automation/readme-freshness` already exist — point them at the reduced scope and let the changelog requirement be checked, not remembered.

### Phase 2 — Kill the duplicates with a decision each (needs Eric)

11. **Morning briefing — pick one producer.** Recommendation: keep the bash pipeline (#2) as the single producer of `briefing.json` for now (it works and runs in prod); keep `hwc_morning_brief` as the only presentation tool; **delete `hwc_morning_status`** or reduce it to reading the same `briefing.json`; archive the Next.js repo with a one-line README tombstone ("superseded by domains/business/morning-briefing; kept for reference"). If the web dashboard is still wanted later, revive it *against briefing.json*, not with its own fetch layer.
12. ~~Finish workbench's last mile~~ — **already done** (live verification: deployed, live session, real tile fetches). Remaining: update the stale `MORNING-HANDOFF.md` to reflect reality or delete it (it actively misled this audit), apply/discard the `nix/staged-for-nixos/` staging, and close the 2 khalt xfails or drop them.
13. **Move the website out of nixos-hwc** into its own repo (it half-is one already — `site_files` is treated as a sub-repo path). Config repo keeps the Caddy route + a fetcher/flake input. Optionally rewrite history afterward (`git filter-repo` on `domains/business/website/site_files`) to reclaim the 174 MB `.git` — destructive, coordinate before doing it.
14. **Evict `workspace/projects/`** (13 apps) to their own repos or a single `~/apps` archive outside nixos-hwc. workspace/ shrinks to its load-bearing set: `nixos-dev/`, `plans/`, `tools/`, `automation/hooks/`, `system/secret-manager.sh`, `utilities/lints/`, `home/scraper/`, `media/youtube-services/`.
15. Dead modules: delete `pihole`, `ai/tools`, `ai/cloud`, `n8n.mcpBridge`, `mediaOrchestrator`, and `.nanoclaw-disabled/` (git keeps them forever), or enable them deliberately this week. "I might want it" is what git history is for.

### Phase 3 — Process changes so it doesn't regrow

16. Adopt the definition of done: **built = deployed + used + one-line changelog entry.** A project that stalls at integration gets finished or archived — never forked into a new stack.
17. AI-output policy: session reports, generated audits, and plans live outside git (or in a single ignored `scratch/`); they get committed only by being merged into the one living doc for that topic.
18. One in, one out for parallel implementations: before building a new take on an existing capability, write the tombstone for the old one first.

---

## Part 4 — Proposed principles (the short list to put in the charter)

1. **A migration ends with `git rm`.** Copy-then-forget is how every duplicate in this repo was born.
2. **Enforced or guideline — nothing in between.** If a law isn't in `nix flake check`, label it a guideline. An always-red or never-run lint is worse than none: it teaches you to ignore red.
3. **Done means deployed and used.** Code-complete with fixtures is 3/4 built, and 3/4-built is the most expensive state — full maintenance cost, zero value.
4. **One producer per fact.** Every piece of information (morning status, health, leads) has exactly one producer; everything else is a consumer of its output.
5. **Config repo holds config.** Anything with its own build/test lifecycle gets its own repo and enters as a flake input (todui is the precedent).
6. **AI output is ephemeral until promoted.** One living doc per topic, edited in place; everything else is scratch.

---

## Part 5 — Live verification addendum (hwc-server, 2026-07-04)

A read-only verification run on hwc-server checked every falsifiable claim above. Scorecard: most findings confirmed (dangling symlink, abandoned Next.js app, healthy MCP gateway and briefing pipeline, dead `kids`/`firestick` fleet references); one refuted (recyclarr placeholders — removed above); three refined (webhook, nix.gc, appointment calculator — corrected above). It also surfaced findings only a live system can show:

### Pattern 6: The terminal step doesn't execute — and runtime state is hard to read

> **Correction (2026-07-05, post-rebuild)**: the first version of this section claimed the running system was ~5 weeks behind the repo ("generation 1092, built 2026-05-30, July-3 commits not deployed"). That was a **misreading of `nixos-rebuild list-generations` output** by the verification run — generation 1092 was `Current=False`; the actual current generation was **1257, built 2026-07-03, already containing HEAD**. A verification rebuild produced a bit-identical store path and created no new generation: **the config deploy loop was closed all along.** The corrected evidence is below.

What genuinely doesn't close:

- **Reboot pending since April.** `booted-system` is an **April-7** build while `current-system` is July-3: the box has been `switch`ed forward for ~3 months without a reboot, so userland is current but the **kernel/initrd are 3 months old** — including any kernel security fixes since.
- **`dedupe.sh` was generated (60k lines, 138 GiB reclaimable) and never executed** — the duplicates are all still on disk.
- **169 system generations retained** — GC runs weekly but pruning was never configured.
- **uptime-kuma still monitors Organizr**, a service deliberately parked (`enable = false`) — monitors outlive the things they watch.
- **1 commit sat unpushed on the server** despite `.claude/`'s auto-push tooling existing precisely to prevent this (since resolved).

This is Pattern 3 (rebuild-instead-of-finish) extended to operations: artifacts get *produced* — scripts, monitors, timers, closures — but the terminal step (reboot, run, prune, retire) doesn't execute, and nothing makes the gap visible.

And the correction episode itself proves the second half of the problem: **runtime state is genuinely hard to read by hand.** The sandbox audit couldn't see it at all; a careful live agent misread it; the truth only surfaced when a rebuild came back bit-identical. Human eyeballs on `list-generations` are not a reliable instrument.

**Recommended fix (small, uses existing infra, now better-motivated)**: add a *config-drift tile* to the morning briefing — computed, not read: HEAD commit vs `/run/current-system` provenance, unpushed commit count, **booted-vs-current mismatch (reboot pending)**, generation count. The pipeline (`run.sh` → `briefing.json` → `hwc_morning_brief` → dashboard/workbench) already exists; this is one more section in `run.sh`. A machine-checked drift number can't be misread the way generation tables can.

### Other live-only findings

1. **Caddy access logging is dead** since the tailnet rename (2026-06-02): per-vhost logs stale since 2025-11-14, zero request lines in the journal. Route-level usage analytics are currently impossible — re-enable per-vhost access logs (also a prerequisite for retiring unused routes with confidence).
2. **Recurring Caddy TLS/ARI error** every ~5h: missing cert metadata JSON for `*.hwc.iheartwoodcraft.com`.
3. **uptime-kuma reports 5 monitors down**: Ollama (:11434 — consistent with the undeployed llama.cpp rewiring commits), Organizr (parked service, stale monitor), Samba, NFS, Estimator (:13443). Zero failed systemd units — the gaps are all at the reachability layer.
4. **Notifications usage measured: 33 messages in 30 days** (~1/day) through the 2,154-line dispatcher+gotify+bridge+igotify stack. The §2.4 overengineering verdict is now quantified.
5. **Fleet corrections**: no `kids` machine exists on the tailnet at all; `firestick` has been offline 149 days; hwc-tablet 173d, raspberrypi 87d. Charter Law-16 lints and `.backups/` reference machines that don't exist — update the lint word-list.
6. Working tree on the server is **clean** (0 modified/untracked), and per the 2026-07-05 correction the config was already deployed — the only repo-vs-runtime gaps are the pending reboot (April kernel) and the since-resolved unpushed commit, not dirty checkouts or deploy lag.

### Added action items

- **Phase 0**: ~~push the unpushed commit; rebuild~~ (done 2026-07-05; rebuild was a verified no-op — config was already live); **schedule a reboot window for hwc-server** (kernel/initrd date to April 7); add `nix.gc` generation pruning; remove/repoint the Organizr uptime-kuma monitor; fix the wildcard-cert metadata error.
- **Phase 1**: config-drift tile in the morning briefing (see above); re-enable Caddy access logs.
- **Phase 2**: decide on `dedupe.sh` — run it (after review) or delete it; retire dead fleet entries (kids, firestick, tablet) from lints, backups, and tailnet.

### Laptop verification addendum (hwc-laptop, 2026-07-05)

The laptop half completed the picture and overturned two more sandbox findings (workbench and tuxedo — corrected inline above). New findings only the laptop could show:

1. **Divergent unpushed history across the fleet (new, real, needs action).** At verification time the server was ahead of origin with one commit (`bd8af2fa`, rclone backport) and the laptop ahead with a *different* one (`b827c3da`, flake update) — neither existing in the other's repo, laptop's origin ref stale. Whichever pushes second gets rejected and needs a fetch+rebase. Two machines committing to the same `main` with no push discipline is a standing merge-conflict generator — and `.claude/`'s auto-push tooling exists precisely for this but evidently isn't installed/active on either machine. **Fix: actually enable the autopush hook (or a post-commit push) on both machines, and make "unpushed commits" a drift-tile metric.**
2. **The dangling `CLAUDE.md` symlink is fleet-wide and *committed*** — the symlink is git-tracked, `AGENTS.md` exists on neither machine, so project instructions loaded on no machine and in every clone. Confirms the repo-level fix on this branch was the right one (merge it).
3. **Reboot-pending is a fleet habit, not a server quirk.** Laptop: current gen July 3, booted gen June 28 — and the gap has a concrete cost: `nvidia-container-toolkit-cdi-generator.service` is failed with an NVML driver/library mismatch (userspace driver 595.84 vs the older running kernel module). Clears on reboot. Both machines run switched-not-rebooted as steady state.
4. **Monitoring blind spot: unit state ≠ process health.** `system76-scheduler` dumped core **224 times in 48 hours** (SIGABRT, `panic_cannot_unwind`) while its unit reported `active (running)` throughout — invisible to `systemctl --failed`, just like the server's five down kuma monitors behind zero failed units. Worth a coredump-count check in monitoring, and its own investigation.
5. **Config-deploy discipline is actually fine fleet-wide**: laptop gen 1398 was built from HEAD ~95 minutes after the commit; the server (per the 2026-07-05 correction) was also current. The real hygiene gaps are **reboots and pushes**, not rebuilds.

**Verification scoreboard, final**: across both machines, live checking refuted or materially corrected **5 sandbox findings** (recyclarr placeholders, tuxedo hash, workbench abandonment, server deploy-lag, nix.gc absence) and confirmed the rest. Two of the five errors were inherited from the repo's own stale docs (`MORNING-HANDOFF.md`) or stale comments (tuxedo). The lesson for future audits is now Principle 7's corollary: **verify against the machine, and keep docs/comments honest enough that they don't poison the next audit.**

### Principle 7 (addition to Part 4)

7. **The repo is not the system.** Every artifact needs its terminal step executed — a commit isn't real until rebuilt, a rebuild until rebooted, a script until run, a monitor until its target exists. Make the gap observable (drift tile) rather than relying on memory.

---

*Full agent-level evidence (file:line for every claim) available in the session that produced this report, plus the 2026-07-04 hwc-server verification report. This document follows its own rules: it supersedes and consolidates; the individual findings above should not be re-committed as separate reports.*
