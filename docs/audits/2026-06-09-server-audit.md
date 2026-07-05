# hwc-server Systematic Audit — 2026-06-09

Full-system audit: live server state, repo cruft, charter compliance, and
NixOS-usage opportunities. Companion deliverables:

- `CHARTER-v12-DRAFT.md` (repo root) — proposed charter rewrite
- `docs/audit/2026-06-09-cleanup.sh` — phased, commented cleanup commands

## Executive Summary

**Live system: healthy.** 0 failed units, 40/40 containers up (some 3+ weeks),
borg backups running nightly to `/mnt/backup` (ZFS), GC + optimise timers active,
journald capped at 1G.

**But ~55 GB is reclaimable** on a root disk at 76%:

| Item | Size | Action |
|------|------|--------|
| Unused podman images (old `:latest` pulls) | 19.4 GB | `podman image prune -af` |
| Orphaned native-ollama models (`/var/lib/private/ollama`) | 17 GB | delete — unit no longer exists; the ollama *container* has its own copies |
| Uncompressed daily pg dumps (`/var/lib/backups`, 14-day window) | ~18 GB → ~2 GB | gzip the dump (config change) |
| Old system generations (133 within 30-day GC window) | several GB | tighten GC to 14d or `nh clean` |

**Repo: significant cruft.** Working tree is 912 MB — ~800 MB is untracked
`node_modules` (gitignored, fine, but `heartwood-site/` is *only* node_modules
with no source). `.git` is 755 MB because history contains Android APKs (93M +
21M), a 48M OpenVINO wheel, a 24M pcap, and old site media.

**Charter: drifted from reality.** Header says v11.2, footer says v11.0, two
sections numbered "5", a phantom `alerts` domain, two real domains (mail,
notifications) ungoverned, three references to a `readme-butler` tool that was
never built, Law 4's "source of truth" (`identity.nix`) never implemented, and
Law 2's violation list flags `hwc.networking` — which the repo actively and
correctly uses. Addressed in the v12 draft.

---

## 1. Live System Findings

### 1.1 Services & containers — PASS
- `systemctl --failed`: empty. All 40 containers running.
- Timers: ~30 maintenance timers, all sane (borg, gc, scrub, cleanups).

### 1.2 Storage
- `/` 76% (336G/468G): `/var/lib/containers` 57G, `/var/lib/backups` 21G,
  `/var/lib/private` 17G (all ollama), `/var/lib/hwc` 13G, nix store 76G.
- `/mnt/media` 73% (5.0T/7.3T) — monitor; `/mnt/hot` 28% — fine.

### 1.3 Duplicated ollama (17 GB orphan)
`domains/ai/ollama/index.nix` (native service) is **not enabled** on the server
— `systemctl is-enabled ollama` → `not-found`. Yet `/var/lib/private/ollama`
holds 17G of models (llama3, codellama, phi3, qwen2.5-coder…) from when it was.
The live ollama is the **container**, with its own model store. The native
state dir is pure orphan. Decide whether the native module itself is still
wanted for the laptop; the server-side state can go either way.

### 1.4 Backups
- Borg → `/mnt/backup/borg-hwc-server` (ZFS, mounted, verified), nightly, ran
  clean 15h ago. Pruning configured in `domains/data/borg/index.nix`.
- PG dumps: `machines/server/config.nix:423` rotates at 14 days — but dumps are
  **uncompressed** 1.2 GB/day plain `.sql`. Gzip (or `pg_dump -Fc`) cuts this
  ~10×. Better: NixOS ships `services.postgresqlBackup` with compression
  built in — replace the custom script (see §4.7).
- A second, separate dump script writes gzipped datax/hwc dumps to
  `/home/eric/backups/postgres` (31M, 61 files, no rotation). Consolidate the
  two mechanisms.

### 1.5 Log noise (cosmetic, inflates journal)
authentik-worker logs **structured INFO JSON to stderr**, so journald records
it at err priority — 3,500 "errors"/day that aren't errors. Same pattern for
authentik-server, uptime-kuma, paperless, firefly. This makes
`journalctl -p err` useless as a health signal. Options: per-container
`--log-level`/syslog severity mapping, or accept and grep around it.
The ollama container also logs a recurring real warning: GPU discovery timeout
(`failure during GPU discovery`) — worth a look if container GPU inference is
expected.

### 1.6 Generations
133 system generations within the 30-day GC window (~4.4 rebuilds/day). Policy
works as designed; if store pressure matters, drop to `--delete-older-than 14d`
or adopt `nh clean all --keep 10 --keep-since 7d`.

---

## 2. Repo Cruft

### 2.1 Certain-dead (delete; all git-revertible except heartwood-site)
| Path | Evidence |
|------|----------|
| `domains/ai/.nanoclaw-disabled/` | decommissioned 2026-05-29, superseded by Hermes (`machines/server/config.nix:541`) |
| `domains/home/apps/.wayvnc-disabled/` | renamed-off, imported nowhere |
| `heartwood-site/` | contains **only** `node_modules/` — no source, referenced by nothing |

### 2.2 Probably-dead (review, then delete or archive)
| Path | Notes |
|------|-------|
| `domains/business/n8n/` | workflow JSON exports; live n8n is `domains/automation/n8n/` |
| `domains/business/receipts/` | pre-Heartwood-API Python project (README dated 2025-03) |
| `ai_agents/` | pre-Claude-Code agent prompt scaffolding, zero references |
| `domains/server/native/.immich-native-reference/` | 4,100-line unimported reference module; keep as docs or delete |
| `workspace/` (selective) | keep `nixos-dev/add-home-app.sh` (used by shell.nix) and `nixos/graph/` (flake app); rest is templates/empty dirs |
| `docs/` | 20+ topic subdirs of accreted AI-generated docs; consolidate to `architecture/ runbooks/ audit/ archive/` |

### 2.3 Git history bloat (755 MB `.git`)
Largest blobs: `tmp/tailscale-android-universal-1.94.1.apk` (93M),
`domains/ai/framework/vendor/openvino…whl` (48M), `workspace_fix/network/capture.pcap` (24M),
`tmp/jellyfin-androidtv….apk` (21M), site media, historical node_modules.
Optional fix: `git filter-repo` to strip blobs >5M from history (~600 MB
saved). **Coordinate first** — rewrites all hashes; every clone must re-clone.
Low urgency; disk is cheap, but clones/CI pay for it forever.

### 2.4 Flake input cruft (`flake.nix`)
| Input | Issue |
|-------|-------|
| `legacy-config = github:eriqueo/nixos-hwc` | the repo imports **itself** as a "migration reference" — migration is done; every `flake update` re-downloads the whole repo. Remove. |
| `agenix-stable` | identical URL to `agenix`, no branch pin — a naming fiction. Replace with `agenix` + `inputs.nixpkgs.follows` (or keep one input). |
| `nixpkgs-tailscale` pin | comment says fixed upstream in 1.98.2; running 1.90.9. Removable at the next flake update once the channel's tailscale ≥ 1.98.2. Pin carries no expiry note — v12 Law 14 fixes this class. |

---

## 3. Charter Compliance Sweep (421 files, 16 domains)

| Law | Result | Detail |
|-----|--------|--------|
| 1 osConfig safety | **PASS** | all guarded |
| 2 namespace fidelity | **PASS** | folder↔namespace verified by sampling |
| 3 path abstraction | **35 violations / 20 files** | worst: `domains/system/mcp/index.nix` (11 — `/opt/n8n-mcp`, `/home/eric/400_mail`, …), `routes.nix:288,301`, youtube, website, morning-briefing |
| 4 permission model | **PASS** | no PGID=1000 |
| 5 mkContainer | **PASS** | no raw oci-container blocks |
| 6/10 option locality | **16 violations** | 16 separate `options.nix` files remain; v11.0 declared this migration complete ("eliminated 37 options.nix files") — it wasn't. Mostly `domains/server/native/ai/*` and `domains/home/apps/*` |
| 7 sys.nix purity | **PASS** | |
| 9 module shape | **1 violation** | `domains/mail/protonmail-bridge/sys.nix` — orphaned, declares options with no index.nix |
| 12 READMEs | **PASS** | all present, current |

**Build-risk conflicts (high priority):**
1. `systemd.services.protonmail-bridge` defined by **both**
   `domains/mail/bridge/sys.nix` and `domains/mail/protonmail-bridge/sys.nix`
   under different option namespaces. Enabling both = eval error. Consolidate.
2. `systemd.services.caddy` defined in `domains/networking/reverseProxy.nix`
   **and** `domains/server/containers/_shared/caddy.nix` (stale legacy copy).
3. `init-media-network` defined in `domains/networking/podman-network.nix`
   **and** `domains/server/containers/_shared/network.nix`.
   For 2–3: verify which is live per machine (Chesterton's Fence), delete the
   stale one, add mutual-exclusion assertions if both must coexist.

---

## 4. NixOS Capabilities You're Not Using

Ordered by leverage for this setup:

1. **`checks.` in the flake (biggest win).** The charter's "Mechanical
   Validation Suite" is a bash snippet humans must remember to run. Wrap each
   lint in `pkgs.runCommand` and expose as `checks.x86_64-linux.charter-*`;
   then `nix flake check` *is* charter enforcement, and CI gets it for free.
2. **CI on the repo.** GitHub Actions (or a self-hosted runner on this box):
   `nix flake check` + `nixos-rebuild dry-build` for both hosts on every push.
   Catches the "builds on laptop, breaks on server" class before switch.
3. **`services.postgresqlBackup`** — native module with compression and
   per-database targets; replaces both hand-rolled dump scripts.
4. **`virtualisation.podman.autoPrune`** — `enable = true; flags = ["--all"];
   dates = "weekly";` makes the 19 GB image pile structurally impossible.
5. **Container image pinning.** Most containers run `:latest` (e.g. ollama).
   Pin tags (ideally digests) so rebuilds are reproducible and upgrades are
   diffs in git, not whatever the registry served. Codified as v12 Law 15.
6. **Remote deployment** — `nixos-rebuild switch --flake .#hwc-server
   --target-host hwc-server --use-remote-sudo` from the laptop, or
   **colmena**/**deploy-rs** for fleet semantics + auto-rollback. One command,
   both machines, no SSH-then-rebuild dance.
7. **`nh`** (nix-helper): nicer rebuild output, and `nh clean all --keep 10`
   as a saner generation policy than raw time-based GC.
8. **treefmt-nix + statix + deadnix** — formatter plus Nix-level dead-code and
   anti-pattern linting, wired into `checks.` (deadnix would have flagged some
   of §2 automatically). Optionally enforced at commit time via git-hooks.nix.
9. **devShells** — `nix develop` shell with agenix, statix, deadnix, the
   npmDepsHash helper, etc., so repo tooling is self-provisioning.
10. **disko + nixos-anywhere** — declarative partitioning; turns bare-metal
    disaster recovery from "restore borg + hand-partition" into one command.
    The borg data covers state; this covers the machine itself.
11. **Binary cache between machines** (harmonia/attic on the server) — modest
    win since laptop=unstable / server=stable share few store paths, but
    useful for shared TS service builds.
12. **specialisation** (laptop more than server) — e.g. GPU-on/off or
    travel/home boot entries without separate configs.

Not recommended: switching agenix→sops-nix (your generator setup is now a
strength), impermanence (high migration cost, low payoff here), k8s-anything.

---

## 5. Phased Cleanup Plan

Exact commands in `docs/audit/2026-06-09-cleanup.sh`.

- **Phase 1 — zero-risk reclaim (no rebuild):** prune unused images (19.4G),
  delete orphaned ollama state (17G), delete certain-dead repo items (§2.1),
  commit.
- **Phase 2 — config changes (rebuild required):** compress pg dumps or adopt
  `services.postgresqlBackup`; add `podman.autoPrune`; remove `legacy-config`
  input; dedupe `agenix-stable`; drop tailscale pin when channel ≥1.98.2.
- **Phase 3 — refactors (one commit each, Chesterton check first):**
  consolidate protonmail-bridge; remove stale `_shared/{caddy,network}.nix`
  duplicates; migrate 16 `options.nix` files into their `index.nix`; sweep 35
  hardcoded paths starting with `domains/system/mcp/index.nix`.
- **Phase 4 — heavy/optional:** triage §2.2 probably-dead dirs; consolidate
  `docs/`; `git filter-repo` history rewrite (coordinate clones); wire charter
  lints into `nix flake check` + CI (§4.1–2).

## 6. Charter v12

`CHARTER-v12-DRAFT.md` rewrites the charter to match reality and close the
audit's structural gaps: fixed versioning/numbering, a 16-domain table that
matches `ls domains/`, corrected law text (paths.nix reference, Law 2
contradiction, Law 4 fiction removed), aspirational tooling dropped, and three
new laws — Repo Hygiene (13), Flake Input Discipline (14), Runtime Hygiene
(15) — that make this audit's findings violations instead of surprises.
Review and promote with `mv CHARTER-v12-DRAFT.md CHARTER.md`.
