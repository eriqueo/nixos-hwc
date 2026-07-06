# Overnight Execution Report — 2026-07-06 (~00:00–01:00)

All 11 decisions from last night's walkthrough are executed, deployed, and
verified — plus four real bugs found and fixed along the way. Both machines:
**0 failed units**. Server: **37/37 containers** (39 minus the two gotify
containers, deliberately). Everything committed and pushed; the auto-push hook
you installed last night pushed every commit itself.

## The 60-second version

| Decision | Outcome |
|---|---|
| Law 12 hybrid README scope | ✅ Charter v12.4 + 52 new module READMEs, lint wired green |
| Two-tier image pinning | ✅ 5 critical images pinned to running versions |
| LibreWolf → Firefox | ✅ Migrated, profile data copied, smoke-tested |
| Briefing single producer + email | ✅ Consolidated; **first email arrives ~06:00** |
| Delete dead modules | ✅ 5 modules + all references gone |
| Website evict + history purge | ✅ Own repo, history rewritten, CMS still running |
| Projects → individual repos | ✅ 9 private GitHub repos created |
| dedupe.sh | ✅ Dry-run verified; **deletion awaits your go** (see below) |
| Gotify decommission | ✅ Executed per the June-11 plan |
| Fleet retirement | ✅ Kept, per your resurrection plan (and `kids` turned out real) |
| Charter principles | ✅ Doctrine §0.5–0.11, v12.4 |

## Bugs found and fixed tonight (not in any plan)

1. **paperless had been crash-looping for weeks** — 1,600+ restarts since boot
   alone. Its bind-mount dirs (`/mnt/hot/documents/{export,staging}`) had
   vanished and were never declared. Now declared via tmpfiles; **paperless is
   running for the first time in a long while** — worth logging in to check it.
2. **redis-main died at boot** — ordering on the podman network isn't enough
   (the gateway IP only appears when the first container starts). Now retries
   until the bridge exists (`Restart=on-failure`).
3. **firefly pin tag scheme** — first pin attempt (`v6.4.22`) doesn't exist
   upstream; correct scheme is `version-6.4.22`. Fixed, firefly + pico active.
4. **The audit was wrong twice**, caught by verification: `ai.tools` was NOT
   "never enabled" (it was live on the laptop — but with zero shell-history
   usage ever, so it died under *deployed + used*); and `machines/kids/` is a
   real registered machine (retro-gaming MacBook), so the Law 16 word-list was
   correct and 1.7 became a no-op.

## How your morning briefing reaches you now

One producer, three consumers:

```
06:00 systemd timer (hwc-server)
  └─ run.sh  →  briefing.json          (sole producer of the fact)
       ├─ https://briefing.hwc.iheartwoodcraft.com   (dashboard)
       ├─ hwc_morning_brief / hwc_morning_status      (workbench + claude.ai — status is now a pure reader)
       └─ NEW: email → eric@iheartwoodcraft.com       (msmtp, proton bridge; render + send path tested tonight)
```

The Next.js morning-briefing repo is tombstoned (SUPERSEDED banner, local +
GitHub). `hwc_morning_status` no longer computes anything on its own — no more
drift between "the briefing" and "the status".

## Why drift should hurt less from here

- **Doctrine now says it** (CHARTER v12.4 §0.5–0.11): migrations end with
  `git rm`; enforced-or-guideline; done = deployed + used; one producer per
  fact; config repo holds config; the repo is not the system.
- **The lints enforce it**: 9 charter checks in `nix flake check`, including
  the new hybrid Law 12 scope (54-README gap burned down tonight, so it wired
  green, not red).
- **The drift tile watches it**: reboot-pending, unpushed commits, dirty trees,
  coredump counts land in the 06:00 briefing — which now also lands in your inbox.
- **Auto-push closes the loop**: every commit tonight was pushed by the hook
  within seconds; the divergent-history incident class is dead.
- **One producer per fact** is now real for the briefing, the website content
  (one repo), and the projects (one repo each).

## What changed where

- **nixos-hwc**: ~20 commits, `c3440a16..d274586a`. ⚠️ **History was rewritten**
  by the site_files purge (`.git` 737→574 MB). Your laptop and the server are
  both on the new history already. Any OTHER clone needs
  `git fetch && git reset --hard origin/main`. Full pre-purge backup:
  `~/nixos-pre-purge-2026-07-06.bundle` (764 MB — delete once confident).
- **New GitHub repos (all private)**: hwc-website, bathroom-planner-api,
  bible-plan, estimate-automation, event-aggregator, mailbot,
  productivity-scripts, receipts-pipeline, site-crawler, youtube-services.
  Local clones in `~/600_apps/`. Secret scans clean.
- **Website runtime**: `/opt/business/website-site` (clone of hwc-website).
  The CMS is running untouched via a bridge symlink
  (`domains/business/website/site_files → /opt/business/website-site`).
  Public site unaffected throughout (it deploys to Hostinger via SFTP).
- **Browser**: `domains/home/apps/firefox/` (Firefox 152.0.4), `firefox-hwc`
  launcher, Hyprland keybind updated, insecure-package permit removed.
  Bookmarks/logins/cookies/extensions copied from LibreWolf; `~/.librewolf/`
  kept as backup. Extensions may ask to be re-enabled on first launch.
  Deliberately NOT ported: resistFingerprinting / FPP `+AllTargets` (your
  documented site-breakage history).

## Needs your hands (small)

1. **dedupe execution** (you gated this on review): manifest re-verified
   tonight — 60,182 files / 138.12 GiB / 0 stale entries. Mostly StepMania
   noteskin micro-files + quarantined music dupes; keep-side prefers
   /mnt/media. Execute with:
   `ssh hwc-server 'cd ~/.nixos/workspace/media/manifests && DRY_RUN=0 bash dedupe.sh'`
2. **CMS cleanup** (the permission layer blocked me from editing the live CMS
   config; the symlink bridge means zero urgency). When convenient, on the server:
   - edit `/opt/business/heartwood-cms/lib/config.js`: replace
     `/home/eric/.nixos/domains/business/website/site_files` → `/opt/business/website-site` (6 lines)
   - `sudo systemctl restart heartwood-cms`
   - remove the bridge symlink + leftovers:
     `~/.nixos/domains/business/website/site_files` (symlink) and
     `site_files.pre-eviction-leftovers/` (old dist/node_modules junk)
3. **First launch of Firefox**: check your extensions re-enabled and log
   into anything that dropped a session.

## Unearthed follow-ups (queued, not urgent — say the word and I'll take any)

- **Gotify runtime tail**: archive/delete `/var/lib/hwc/gotify`; drop the
  gotify branch from the live `sys:router:notify` n8n workflow (and its
  provisioning JSON in the repo); 3 ad-hoc scripts in `workspace/monitoring/`
  still call `hwc-gotify-send` — rewire to hwc-notify or delete.
- **Alerting gaps created by the decommission** (flagged, deliberate):
  gluetun VPN-health alerts had gotify as their only channel — auto-restart
  still works but flaps are silent; mail-health criticals are Slack-webhook
  only now. Rewire either to hwc-notify if you want pages.
- **system76-scheduler**: one SIGABRT 4s after boot, clean since. The
  `coredumps_24h` drift tile will show if it's actually done; if it climbs,
  disable + report upstream.
- **paperless**: now that it runs, verify the web UI and data
  (paperless.hwc.iheartwoodcraft.com or :8102).
- **xps**: not rebuilt tonight (all evals pass; it picks everything up on its
  next rebuild). Also pre-existing warning there: `backup.enable = true` with
  no methods configured.
- **My webhook probe** sent one junk `{"_probe":true}` POST to the reactivated
  appointment workflow — if a stray booking/lead shows up, that's it.
- **briefing email at 06:00**: the render + a real msmtp send were both tested
  tonight, but the first full in-service run is this morning — if no email
  arrived, `grep STEP.5 ~/.nixos/domains/business/morning-briefing/logs/run.log`
  on the server (failure mode logs a WARN, never breaks the briefing).
