# Dead-Code Investigation Prompt — Parallel Server/Infrastructure Trees

## Context

Last session deleted 9 pieces of dead code from nixos-hwc (commits `92338a17`..`18c1a683` on `main`), culminating in `domains/infrastructure/`. While doing that, I observed several files that **reference `hwc.infrastructure.*` options** but appear to be **unimported by any live machine**. I did not delete them — scope creep risk. This investigation determines whether they're truly dead and removes them if so.

## What "live" means

The five machines registered in `flake.nix`'s `nixosConfigurations`:
- `hwc-laptop` → `machines/laptop/config.nix`
- `hwc-server` → `machines/server/config.nix`
- `hwc-xps` → `machines/xps/config.nix`
- `hwc-kids` → `machines/kids/config.nix`
- `hwc-firestick` → `machines/firestick/config.nix`

Plus the two `homeConfigurations` (`eric@hwc-laptop`, `eric@hwc-server`).

**Anything not reachable from these by transitive `imports = [...]` is dead.**

## Suspected dead trees (from prior session)

```
domains/server/native/ai/ollama/index.nix
domains/server/native/jellyfin/index.nix
domains/server/native/frigate/index.nix
domains/server/native/retroarch/index.nix
domains/server/native/media/index.nix
domains/server/containers/tdarr/parts/config.nix
domains/server/containers/immich/parts/config.nix
domains/system/networking/samba.nix
domains/server/monolith_breakdown.sh        # standalone script, almost certainly dead
```

These all reference `hwc.infrastructure.*` (a namespace that no longer exists in declarations — its `options.nix` files were deleted last session). If they were live, the post-deletion build of hwc-server would have failed; it did not. But "didn't fail this time" ≠ "definitely unreachable" — confirm by tracing imports.

## What NOT to touch (live, verified last session)

`domains/server/containers/_shared/{network,caddy,directories}.nix`, `domains/server/containers/arka/`, `domains/server/native/ai/jobber-mcp/` — these ARE imported by `machines/server/config.nix`. Inspect them to see whether THEY transitively reach the suspected-dead files.

## Methodology (do not skip steps)

### Step 1 — Build the live import closure

For each live machine, list every `.nix` file in its transitive import graph. Either:
- Use `nix-instantiate --eval --strict --json .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath` and walk derivations, OR
- Recursively parse `imports = [...]` from `machines/<host>/config.nix` outward (less robust but transparent)

Save the union of these closures as `LIVE_CLOSURE` (file path list).

### Step 2 — Find files referencing dead namespaces

```bash
rg -ln 'hwc\.infrastructure\.' /home/eric/.nixos/domains/ /home/eric/.nixos/profiles/
```

For each hit, check membership in `LIVE_CLOSURE`. Files in the closure → still-broken live code (investigate root cause). Files NOT in the closure → candidate for deletion.

### Step 3 — Generalize: find ALL unreachable .nix files

Don't just check the namespace. Compute `find domains/ profiles/ -name '*.nix'` minus `LIVE_CLOSURE`. The diff is the broader dead-file set. Group by domain subdir for review.

Note: `_shared/` files in `domains/server/containers/` ARE used by other containers via direct imports — exclude from "dead" until you've checked.

### Step 4 — Authoritative sanity check

For each candidate set you plan to delete:
```bash
git rm -r <paths>
nix build .#nixosConfigurations.hwc-laptop.config.system.build.toplevel --dry-run
nix build .#nixosConfigurations.hwc-server.config.system.build.toplevel --dry-run
nix build .#homeConfigurations."eric@hwc-server".activationPackage --dry-run
nix build .#homeConfigurations."eric@hwc-laptop".activationPackage --dry-run
```

If any fails, `git restore --staged . && git checkout -- <paths>`, narrow the set, re-test. **hwc-xps has a pre-existing unrelated failure** (`hyprland.configType` in `profiles/session.nix`) — that's not yours to fix; just don't make it worse. `hwc-kids` and `hwc-firestick` are nice-to-check but lower priority.

### Step 5 — Workflow rules (from session memory)

- One conceptual change per commit. Group by domain subtree if cohesive (e.g., `chore(server): delete dead native/ai/ollama parallel implementation`).
- `git restore --staged .` before each commit to clear any pre-existing staging. Pre-existing modification in `domains/paths/paths.nix` is the user's in-progress edit — leave it alone.
- NEVER `git add -A`.
- Each commit message must quote the verification command used (so future audits can re-verify).
- Update touched domain READMEs (Layout block + dated Changelog entry). Today's date in `currentDate` from system context.
- Pause between commits. No rebuild until the end.
- ONE `snix` (`sudo nixos-rebuild switch --flake .#hwc-laptop`) at the end. Confirm new generation is active and check `systemctl --failed` — only pre-existing failures (`home-eric-600_shared.mount` NFS mount, network-dependent) are OK.

## Specific questions to answer in the report

1. Is `domains/server/native/` an entire dead parallel tree, or do some subdirs still feed live machines?
2. Are the `domains/server/containers/{tdarr,immich,frigate,...}/parts/` files supplanted 1:1 by `domains/media/<service>/` equivalents? Cross-reference with what `machines/server/config.nix` actually sets (`hwc.media.frigate.enable`, `hwc.media.immich`, etc.).
3. Is `domains/system/networking/samba.nix` referenced by `domains/system/index.nix` or any of its imports? It declared `hwc.infrastructure.samba` — was there ever a corresponding `options.hwc.infrastructure.samba` declaration, or has it been broken-but-unimported for a while?
4. Are there other dead namespaces beyond `hwc.infrastructure.*`? Check for `hwc.server.*` namespace consumers vs declarers — Charter v11.0 said `domains/server/` was removed but the dir still exists on disk.
5. Quantify the cleanup: lines deleted, file count, % of total `.nix` files.

## Out of scope

- Fixing the `hwc-xps` `hyprland.configType` issue (separate task).
- Refactoring live code, even if you spot Charter violations during exploration. Log them in the report; don't fix them in this PR.
- Deleting anything that requires touching `flake.nix`, `machines/*/config.nix`, or `profiles/core.nix`.

## Definition of done

- All dead files removed in cohesive per-domain commits.
- All four live build targets (laptop, server, server-HM, laptop-HM) pass `--dry-run`.
- `snix` activates cleanly on the laptop, only pre-existing failures remain.
- Report: list of deleted paths, line counts, any newly-discovered dead namespaces, any Charter violations spotted (for follow-up), and a final `rg -ln 'hwc\.infrastructure\.' domains/ profiles/` showing zero matches.
