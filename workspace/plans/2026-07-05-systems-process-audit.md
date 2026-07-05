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

Workbench shows the same signature from the other side: hexagonal architecture, 120 passing tests, 3,465 lines of test code, zero `NotImplementedError` — and per `MORNING-HANDOFF.md` it has **never round-tripped one live MCP response or spawned one real zellij pane**. All six remaining items on its handoff list are integration steps. It is beautifully engineered and not yet *used*.

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

Live risks found on the way: `tuxedo/parts/package.nix:29` ships `PLACEHOLDER — replace with the real hash` (laptop verification pending); the website's appointment-calculator webhook **404s live** (verified: `webhook/calculator-appointment` → 404; the sibling `webhook/calculator-lead` → 200 and works — one inactive n8n workflow, not a dead calculator). ~~recyclarr falls back to placeholder API keys~~ — **refuted by live check**: recyclarr synced clean the morning of verification, no placeholder/401/403 in 14 days of journal; the fallback code path exists but is not being hit.

### 2.4 Complexity outliers (overengineering candidates)

| Area | Size | Question to ask |
|---|---|---|
| `notifications/` | 2,154 lines | Hexagonal dispatcher + gotify + igotify + bridge — to send yourself notifications. Could one dispatcher + one channel do it? (A gotify-decommission plan already exists in workspace/plans.) |
| `mail/` | 46 files | Every component split into parts/. Fragmentation cost now exceeds navigation benefit. |
| `paths/paths.nix` | 640 lines, 1 file | The opposite drift — the only monolith in the repo. |
| Law 12 as written | per-subdomain READMEs, 4 sections + changelog | 52% missing proves the contract exceeds manual capacity. Reduce scope (top-level domains only) or automate — don't keep a law that's half-false. |
| workbench | full hexagonal core, 2 shells, 18 test files | For a personal TUI that hasn't fetched a live tile. Architecture is ahead of usage by two steps. |

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
12. **Finish workbench's last mile instead of adding anything to it**: point it at the live `:6200` gateway, verify one real tile, test one real zellij pane. Its handoff list is six integration items; that's the whole remaining project. No new hubs until a live tile renders.
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

### Pattern 6: The deploy loop doesn't close (the biggest finding of the whole audit)

- **The running system is ~5 weeks behind the repo.** Live generation 1092 was built **2026-05-30**; repo HEAD is **2026-07-03**. The entire July-3 batch — qbittorrent VPN hardening, sabnzbd Caddy whitelist, rclone backport, llama.cpp rewiring — is committed but **not deployed**.
- **The booted system is older still** (April 7 build): a switch happened May 30 without a reboot since.
- **Local `main` is 1 commit ahead of origin** (unpushed), despite `.claude/`'s auto-push tooling existing precisely to prevent this.
- Same shape elsewhere: `dedupe.sh` was generated (60k lines, 138 GiB reclaimable) and **never executed** — the duplicates are all still on disk; 169 generations accumulate because pruning was never configured; uptime-kuma still monitors Organizr, which is deliberately parked (`enable = false`).

This is Pattern 3 (rebuild-instead-of-finish) extended to operations: artifacts get *produced* — commits, scripts, monitors, timers — but the terminal step (rebuild, reboot, run, prune, retire) doesn't execute, and nothing makes the gap visible. The charter governs the repo; **nothing governs the distance between the repo and the machine.**

**Recommended fix (small, uses existing infra)**: add a *config-drift tile* to the morning briefing — HEAD vs running-generation age, unpushed commit count, booted-vs-current generation mismatch. The pipeline (`run.sh` → `briefing.json` → `hwc_morning_brief` → dashboard/workbench) already exists; this is one more section in `run.sh`. Drift you see every morning at 6am is drift that closes.

### Other live-only findings

1. **Caddy access logging is dead** since the tailnet rename (2026-06-02): per-vhost logs stale since 2025-11-14, zero request lines in the journal. Route-level usage analytics are currently impossible — re-enable per-vhost access logs (also a prerequisite for retiring unused routes with confidence).
2. **Recurring Caddy TLS/ARI error** every ~5h: missing cert metadata JSON for `*.hwc.iheartwoodcraft.com`.
3. **uptime-kuma reports 5 monitors down**: Ollama (:11434 — consistent with the undeployed llama.cpp rewiring commits), Organizr (parked service, stale monitor), Samba, NFS, Estimator (:13443). Zero failed systemd units — the gaps are all at the reachability layer.
4. **Notifications usage measured: 33 messages in 30 days** (~1/day) through the 2,154-line dispatcher+gotify+bridge+igotify stack. The §2.4 overengineering verdict is now quantified.
5. **Fleet corrections**: no `kids` machine exists on the tailnet at all; `firestick` has been offline 149 days; hwc-tablet 173d, raspberrypi 87d. Charter Law-16 lints and `.backups/` reference machines that don't exist — update the lint word-list.
6. Working tree on the server is **clean** (0 modified/untracked) — repo-vs-runtime drift is entirely deploy-lag and origin-sync, not dirty checkouts.

### Added action items

- **Phase 0**: push the unpushed commit; rebuild + reboot hwc-server (July-3 batch, incl. security-relevant qbittorrent VPN hardening, is not live); add `nix.gc` generation pruning; remove/repoint the Organizr uptime-kuma monitor; fix the wildcard-cert metadata error.
- **Phase 1**: config-drift tile in the morning briefing (see above); re-enable Caddy access logs.
- **Phase 2**: decide on `dedupe.sh` — run it (after review) or delete it; retire dead fleet entries (kids, firestick, tablet) from lints, backups, and tailnet.
- **Still pending on hwc-laptop**: workbench real usage (V5), tuxedo placeholder hash (V9), laptop git/units state.

### Principle 7 (addition to Part 4)

7. **The repo is not the system.** Every artifact needs its terminal step executed — a commit isn't real until rebuilt, a rebuild until rebooted, a script until run, a monitor until its target exists. Make the gap observable (drift tile) rather than relying on memory.

---

*Full agent-level evidence (file:line for every claim) available in the session that produced this report, plus the 2026-07-04 hwc-server verification report. This document follows its own rules: it supersedes and consolidates; the individual findings above should not be re-committed as separate reports.*
