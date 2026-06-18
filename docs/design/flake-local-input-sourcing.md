---
title: Durable multi-machine sourcing for local-app flake inputs
created: 2026-06-18
updated: 2026-06-18
tags: [design, nixos, flake, home-manager]
status: proposal
related:
  - brain/tech/wiki/nixos/flake-path-inputs-vs-git-across-machines.md
  - feedback_app_dev_build_pattern (memory)
---

# Durable multi-machine sourcing for local-app flake inputs

## Problem statement

The nixos-hwc repo consumes three of Eric's own apps — `todui`, `khalt`,
`workbench` — as flake inputs. Both naive shapes for "an app I'm hacking on
locally" have already failed on hwc-laptop ↔ hwc-server:

- **`path:/home/eric/600_apps/<app>`** content-hashes the working tree, so
  Syncthing-driven mtime/content drift produces `NAR hash mismatch` on the
  *other* machine the moment either side rebuilds.
- **`git+file:///home/eric/600_apps/<app>`** locks a commit SHA, which fixes the
  NAR-hash class but introduces a second class: the committed `flake.lock` is
  shared, but each machine has its own `~/600_apps/<app>` clone with its own
  history. The machine that didn't make the commit dies with
  `error: getting Git object '<sha>': object not found`.

The authoritative analysis (recipe-vs-fridge framing, both failure modes, the
manual bare-hub stopgap) lives in
[`brain/tech/wiki/nixos/flake-path-inputs-vs-git-across-machines.md`](../../../900_vaults/brain/tech/wiki/nixos/flake-path-inputs-vs-git-across-machines.md);
this design assumes its findings rather than re-deriving them. The triggering
incident is **workbench 2026-06-15**: PR #43 pinned `workbench` to
`db79d796…` (built on the laptop); `snix` on hwc-server failed with
`object not found` because the server's local workbench clone had only the root
commit. Resolution was a manual one-off bare hub at
`~/git/workbench.git`. `todui` and `khalt` later required the same
hand-treatment. The recurring failure deserves a documented, decided-in-advance
shape — this doc — instead of another per-incident scramble.

Two structural amplifiers make it worse:

1. The HM modules import unconditionally
   (`imports = [ inputs.<app>.homeManagerModules.<app> ]` at
   `domains/home/apps/{todui,workbench,khalt}/index.nix`), so even a host that
   never *enables* the app — hwc-server, headless — still forces the input to
   resolve at eval time. A broken input bricks every machine, not just the
   one that uses the app.
2. `~/600_apps` was Syncthing-replicated for most of this period, which is the
   only reason `path:` ever looked viable and the reason `git+file:` hubs took
   so long to land (Syncthing kept partial git state in flight). `600_apps`
   left Syncthing on 2026-06-16; the design should not silently re-acquire a
   dependency on filesystem replication.

## Options evaluated

### Option A — Auto-provisioned bare hubs in Nix, keep `git+file:` URLs

**How it works.** A new module `hwc.development.localFlakeHub.<app> = { path = "/home/eric/git/<app>.git"; seedFrom = "/home/eric/600_apps/<app>"; };`
runs on every machine. At activation it `git init --bare` the hub if absent,
adds it as `origin` on the seed clone if missing, and (on the "owner" machine
only) seeds it from the local working tree. The flake input URL stays
`git+file:///home/eric/600_apps/<app>` — the fix is that every machine's
`~/600_apps/<app>` clone is now hub-backed, so `git fetch && git reset --hard
origin/main` is enough to bring any locked commit into reach. The
[brain note's instances section](../../../900_vaults/brain/tech/wiki/nixos/flake-path-inputs-vs-git-across-machines.md)
shows this is exactly the manual ritual that resolved the 2026-06-15
workbench/khalt incidents — Option A is "freeze the ritual into Nix."

**Consumer `flake.nix` URL.**

```nix
workbench = {
  url = "git+file:///home/eric/600_apps/workbench";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

**Infrastructure required.** A bare hub per app on hwc-server (auto-created),
SSH from every other machine to `eric@hwc-server.ocelot-wahoo.ts.net`. No
network beyond the tailnet. No external service.

**Ship-a-change workflow.**

```bash
cd ~/600_apps/workbench
$EDITOR src/foo.py
git commit -am "feat: x"
git push                       # to ~/git/workbench.git on hwc-server
# on each consuming machine:
git -C ~/600_apps/workbench pull
cd ~/.nixos && nix flake update workbench && hms          # or sudo nixos-rebuild switch
```

**Fresh machine.** Module brings up the hub-symlink config, but `~/600_apps/<app>`
still has to be cloned by hand: `git clone eric@hwc-server.ocelot-wahoo.ts.net:git/<app>.git ~/600_apps/<app>`.
First build then succeeds because the clone is already at the locked rev. The
module can do this clone too, at the cost of more activation-time SSH.

### Option B — Server-hosted `git+ssh://` inputs

**How it works.** Move the canonical history to a bare hub on hwc-server
(same as Option A) but switch the flake input URL itself to point at the
remote. Every machine fetches the locked rev directly into the Nix store at
eval/build time; no per-machine `~/600_apps/<app>` clone is required for the
build to resolve. Live iteration still happens in `~/600_apps/<app>` (the
maintainer's local clone, wired to the same hub), it's just no longer on the
build's critical path.

**Consumer `flake.nix` URL.**

```nix
workbench = {
  url = "git+ssh://eric@hwc-server.ocelot-wahoo.ts.net/~/git/workbench.git";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

**Infrastructure required.** Bare hubs on hwc-server (as in A). SSH
reachability from every consumer to hwc-server, including during `nix flake
update` and during builds on machines that don't already have the input in the
store. SSH-agent forwarding or a deploy key for any host that runs `nix
build` without an interactive user (none today, but worth noting).

**Ship-a-change workflow.**

```bash
cd ~/600_apps/workbench
git commit -am "feat: x" && git push
cd ~/.nixos && nix flake update workbench && hms
```

**Fresh machine.** `nix flake update` / build is sufficient — nix fetches the
locked rev over SSH on demand. No `~/600_apps` clone required to build. For
live iteration the maintainer still clones the hub.

### Option C — Sync timer that pins every clone to the locked rev

**How it works.** Keep `git+file:///home/eric/600_apps/<app>` URLs. Install a
systemd user timer on every machine that reads `~/.nixos/flake.lock`,
extracts each app's locked rev, and runs
`git -C ~/600_apps/<app> fetch && git reset --hard <locked-rev>`. The local
clone is therefore always at whatever commit the lock says, and a hub still
exists for the timer to fetch from. The timer is the "you forgot to pull"
guard.

**Consumer `flake.nix` URL.** Same as Option A
(`git+file:///home/eric/600_apps/<app>`).

**Infrastructure required.** Bare hubs (as in A); a per-user systemd timer per
machine; a small script that parses `flake.lock` JSON. Destroys any
uncommitted local edits in `~/600_apps/<app>` on every tick (the `--hard`),
which is the whole point but is also a sharp edge.

**Ship-a-change workflow.**

```bash
cd ~/600_apps/workbench && git commit -am "x" && git push
cd ~/.nixos && nix flake update workbench && hms
# every other machine: next timer tick (or `systemctl --user start
# flake-input-sync.service`) brings its clone to the new rev automatically.
```

**Fresh machine.** Module enables the timer; first tick clones missing apps
from the hub. Build then succeeds. Adds activation surface area for what is
otherwise a code-free design.

### Option D — Private `github:` inputs

**How it works.** Push each app to a private GitHub repo
(`eriqueo/<app>`); pin via `github:eriqueo/<app>`. The locked rev lives on
GitHub, which every machine can reach over HTTPS. Private fetch uses an
agenix-managed read-only PAT wired into `nix.extraOptions` via
`access-tokens = github.com=...`. This is the pattern already documented in
the user-memory note `feedback_app_dev_build_pattern`.

**Consumer `flake.nix` URL.**

```nix
workbench = {
  url = "github:eriqueo/workbench";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

**Infrastructure required.** A private GitHub repo per app; a PAT (already
provisioned as `github-flake-token.age`); `nix.extraOptions` writing the
`access-tokens` config; no tailnet/SSH/hub on hwc-server.

**Ship-a-change workflow.**

```bash
cd ~/600_apps/workbench
git commit -am "x" && git push    # to eriqueo/workbench on GitHub
cd ~/.nixos && nix flake update workbench && hms
```

**Fresh machine.** Build works immediately as long as the access token
material is in place. No local clone required for the build. Iteration still
happens by cloning from GitHub into `~/600_apps/<app>`.

## Comparison matrix

| Criterion | A — Auto hubs (`git+file:`) | B — `git+ssh://` to hub | C — Sync timer to locked rev | D — Private `github:` |
|---|---|---|---|---|
| Reproducible across machines | ✅ (lock + hub presence) | ✅ (lock + hub presence) | ✅ (lock + timer convergence) | ✅ (lock + GitHub) |
| Works on a fresh machine out of the box | ⚠️ needs hub clone of `~/600_apps/<app>` | ✅ build only; clone optional | ⚠️ first timer tick must complete | ✅ pure |
| Works fully offline | ✅ once hub is reachable on LAN/tailnet | ✅ once hub is reachable on LAN/tailnet | ✅ once converged; tick needs hub | ❌ requires GitHub reachability |
| Infrastructure introduced | bare hub per app on hwc-server + activation logic | bare hub per app on hwc-server | bare hub + per-machine systemd timer | GitHub private repo + PAT (already shipped) |
| Still supports live `path:` swap | ✅ (URL stays local-ish; comment in `flake.nix` survives) | ⚠️ swap means changing URL scheme, not just a `path:` substitution | ✅ same as A | ✅ swap to `path:` for a session is unaffected |
| Failure mode if maintainer forgets the workflow | "`git push` then `nix flake update`" — if push to hub is forgotten, every other machine breaks at next rebuild | same as A | timer hides the forgotten push for ≤ tick interval, then breaks identically | "`git push` to GitHub then `nix flake update`" — if push is forgotten, every machine breaks identically; GitHub PR UI surfaces the omission |
| Blast radius of a bad pin | Every machine that imports the module (today: all of them, see gating section) | Same | Same | Same |
| Trust boundary expanded | None (LAN/tailnet, existing SSH) | None (LAN/tailnet, existing SSH) | None | GitHub.com + PAT scope |
| Operational state to maintain | hubs + per-machine clones + flake URLs | hubs + flake URLs | hubs + per-machine clones + timer units + flake URLs | GitHub repos + token rotation |

## Unconditional-import gating

All three HM modules currently look like:

```nix
{ config, lib, inputs, ... }:
let cfg = config.hwc.home.apps.<app>; in
{
  imports = [ inputs.<app>.homeManagerModules.<app> ];
  options.hwc.home.apps.<app>.enable = lib.mkEnableOption "...";
  config = lib.mkIf cfg.enable { programs.<app> = { ... }; };
}
```

The `imports` line runs **before** `config` is evaluated — that's a hard
Nix-module invariant, not something `lib.mkIf` can route around. You cannot
write `imports = lib.mkIf cfg.enable [ ... ]` and get the intuitive meaning:
`mkIf` is a `config`-time construct; in `imports` position it either errors or
evaluates the predicate before options exist. So every machine that *imports*
this file forces `inputs.<app>` to resolve, which is exactly why hwc-server
gets bricked by a workbench pin it never uses.

**Proposal.** Move the `imports` decision *up* one level — into whichever
profile/role aggregator actually decides "this host runs the app." Concretely:

- Keep each HM module's `imports = [ inputs.<app>.homeManagerModules.<app> ];`
  as-is — the module remains complete when imported.
- Stop importing the wrapper from any host whose profile doesn't enable the
  app. The decision belongs at the profile layer (`profiles/<role>.nix`),
  which already chooses which app-wrappers to pull in; hwc-server's profile
  should not list these three at all.
- Where a profile genuinely needs to be "soft" — e.g. a generic role that
  *might* enable the app on some hosts — express the choice with a guarded
  import file:

  ```nix
  # profiles/workstation/parts/optional-tui-apps.nix
  { config, lib, inputs, ... }:
  let want = config.hwc.home.apps.todui.enable
          || config.hwc.home.apps.workbench.enable
          || config.hwc.home.apps.khalt.enable;
  in lib.mkIf false {}  # placeholder; real soft-import below
  ```

  …and put the actual `imports` behind a host-list literal in the profile,
  not a runtime predicate. The rule: **input forcing is a static, per-host
  decision**, expressed in profile composition, not in `config = lib.mkIf …`.

This change is independent of which sourcing option (A/B/C/D) we pick: it
shrinks the blast radius from "every machine" to "machines that actually run
the app," which makes a bad pin a localized incident instead of a fleet
outage.

## Recommendation

**Adopt Option D (private `github:` inputs) plus the import-gating change.**

Rationale, against the matrix:

- D is the only option that scores ✅ on both "fresh machine out of the box"
  and "ship-a-change workflow is one push" without introducing per-host
  activation logic. A and B require a bare hub on hwc-server to physically
  exist before any other machine can build; D's "infrastructure" already
  exists (private repo + agenix PAT, per `feedback_app_dev_build_pattern`).
- The single column D loses on — *works fully offline* — is not load-bearing
  for this fleet: hwc-laptop and hwc-server both have reliable internet
  whenever they are doing a rebuild, and the Nix store caches the locked
  fetch for offline rebuilds thereafter.
- C is rejected because a systemd timer that does `git reset --hard` on a
  directory the maintainer also edits live is a foot-gun whose payoff is
  small (saves one `git pull`).
- A and B remain viable fallbacks if the GitHub trust boundary becomes
  unacceptable (e.g. a future air-gap requirement). The migration cost A↔D is
  one URL line per app, so the decision is reversible.
- Gating fixes the *blast radius* regardless of the sourcing scheme and
  should land alongside D so that the next bad pin (in any scheme) does not
  brick hosts that don't consume the app.

In practice, commit
[`6d3079d6`](https://github.com/eriqueo/nixos-hwc/commit/6d3079d6) on
`origin/main` already migrated all three apps to `github:eriqueo/<app>`, so
the recommendation is "ratify D and finish the second half (gating)." The
follow-up card this design names is:

> **`06 — gate unconditional-import of app inputs on profile membership`** —
> remove `imports = [ inputs.<app>.homeManagerModules.<app> ]` from any
> machine profile that does not enable the app (starting with hwc-server),
> and document the rule in `domains/home/apps/README.md`.

## Migration plan

1. **Confirm D is in place.** `flake.nix` already has `url =
   "github:eriqueo/<app>"` for all three apps (commit `6d3079d6`, on
   `origin/main`); the `flake.lock` pins revs reachable on GitHub. No change
   required here for the design to be live.
2. **Land the import-gating card (06) one app at a time.** Sequence:
   `workbench` first (it caused the 2026-06-15 incident and is enabled only
   on hwc-laptop), then `todui`, then `khalt`. For each:
   - In the hwc-server profile (and any other host that does not enable the
     app), stop importing the wrapper module.
   - On hwc-laptop, leave the wrapper imported — behavior is unchanged.
   - `nix flake check` + `hms` on hwc-laptop, `sudo nixos-rebuild dry-build`
     on hwc-server, before any switch.
3. **Do not disturb hwc-server's stashed working trees.** The brain note
   records that hwc-server's pre-incident workbench changes live in
   `stash@{0}` of `~/600_apps/workbench`. The migration touches `~/.nixos`
   only; `~/600_apps/*` is left strictly alone, and `600_apps` remains
   git-only (not Syncthing).
4. **Tear down the manual bare hubs *only after* the gating card ships** and
   one rebuild cycle proves no machine still needs `~/600_apps/<app>` to
   resolve an input. Hubs at `~/git/{workbench,todui,khalt}.git` can stay
   indefinitely as belt-and-suspenders.
5. **Document the workflow** in `domains/home/apps/README.md` under
   `## Changelog`: "Apps are sourced from private `github:eriqueo/<app>`
   inputs; iterate live in `~/600_apps/<app>` via its devShell; ship via push
   to GitHub then `nix flake update <app>` in `~/.nixos`."

## Out of scope

- Moving the apps' source out of `~/600_apps/` or restructuring those repos.
- Rewriting `flake.lock` history or any `git push --force` to GitHub.
- Replacing agenix or rotating the existing `github-flake-token` (separate
  routine).
- Touching the apps' own `flake.nix`/`pyproject.toml`/devShells.
- Introducing CI for the apps themselves (a worthwhile future card, but not
  required to retire the recurring `object not found` failure).
- Any change to `~/600_apps`'s sync model — it stays git-only post-2026-06-16.
