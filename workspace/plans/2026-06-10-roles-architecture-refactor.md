# Roles Architecture Refactor + Home Domain Remediation

**Date**: 2026-06-10
**Status**: SPEC APPROVED — ready for execution by a single Fable session
**Spec'd with**: Eric (interactive session, 2026-06-10)
**Scope**: `profiles/`, `flake.nix`, `machines/`, `domains/home/`, CHARTER.md
**Companion findings**: full home-domain audit + machine-file inventory (summarized in §9/§10)

---

## 0. Why (one paragraph)

The repo has three layers — domains (capabilities), profiles (menus), machines (instances) —
but only domains have an enforced contract. Result: `machines/server/config.nix` grew to
1,121 lines, the HM lane has only one profile (laptop-GUI-flavored) so the server's HM config
was dumped into its machine file, profile names don't reveal their lane (`session.nix` is
system-lane, `home-session.nix` is HM-lane), and an audit agent with the whole repo in view
gave wrong advice because the wiring is asymmetric. This plan makes profiles a **role layer**
with a crisp contract, makes machine membership a **data table in flake.nix**, shrinks
machine files to hardware + genuine one-offs, and lands the home-domain audit fixes into the
new shape.

## 1. Decisions already made (LOCKED — do not relitigate)

1. Profiles become **roles**: one folder per role, containing lane halves named
   **`sys.nix`** (NixOS lane) and **`home.nix`** (HM lane). Names chosen to match existing
   repo vocabulary (domains' Law-7 `sys.nix`; machines' `home.nix`). A half that has nothing
   to say does not exist.
2. **Roles never import roles.** Composition happens only in the machine's role list.
   (Today `gaming.nix` and `firestick.nix` import `core.nix` — this coupling is removed.)
3. **No `machine.nix`.** The machine registry is a data table in `flake.nix` (§3). Glue
   resolves roles → halves. `machines/<m>/` keeps `hardware.nix` + thin `config.nix` /
   `home.nix` holding ONLY genuine one-offs (§4).
4. **The home lane is OS-agnostic by design** (Eric's framing: HM is a product NixOS merely
   happens to host — cf. openSUSE). `profiles/*/home.nix` must obey the same Law-1 handshake
   rules as `domains/home/` modules (evaluatable with `osConfig = {}`).
5. **One toggle mechanism**: imports are structural (domains always fully imported via index
   aggregators), options are behavioral. A profile/role is *nothing but* a named bundle of
   `hwc.*` option flips + domain imports. No packages, no derivations, no inline services.
6. **8 roles**: `base, desktop, server, business, monitoring, gaming, appliance, mail`.
   Business is its own role (8 server-only subdomains + the n8n automation stack — coherent
   "Heartwood operations" concept, portable to a future dedicated box).
7. Naming: never use "home" as a *profile name* prefix (the lane filename `home.nix` is the
   only place the word appears — paired with `sys.nix` it is unambiguous).

### Deferred by Eric (explicitly out of scope — do NOT do these)
- SSH password-auth contradiction (core.nix policy vs 3 machines' mkForce true). Leave all
  current mkForce overrides in place, byte-for-byte.
- Jellyfin plaintext API key rotation/agenix (`machines/server/config.nix:937`). Leave as-is;
  carry the literal through any file moves unchanged.

## 2. Target layout

```
profiles/
  base/        sys.nix  home.nix    # every machine
  desktop/     sys.nix  home.nix    # laptop, xps — screen + human
  server/      sys.nix              # server, xps — infra serving (podman, couchdb, gotify, sudo rules…)
  business/    sys.nix              # server — hwc.business.* + hwc.automation.{n8n,mqtt}
  monitoring/  sys.nix              # server, xps — pure observability (prometheus/grafana/alertmanager/…)
  gaming/      sys.nix  home.nix    # kids (home.nix only if HM content emerges; start sys-only, see §5)
  appliance/   sys.nix              # firestick
  mail/        home.nix             # server — hwc.mail menu (bridge/aerc/notmuch/calendar/health)

machines/<m>/
  hardware.nix                      # unchanged (pure hardware)
  config.nix                        # one-offs only (target ≤ ~100 lines incl. comments)
  home.nix                          # one-offs only (target ≤ ~40 lines)
```

## 3. flake.nix machine registry + glue

Single source of truth for the fleet:

```nix
machines = {
  server    = { channel = "stable";   roles = [ "base" "server" "business" "monitoring" "mail" ]; };
  laptop    = { channel = "unstable"; roles = [ "base" "desktop" ]; };
  xps       = { channel = "stable";   roles = [ "base" "desktop" "server" "monitoring" ]; };
  kids      = { channel = "stable";   roles = [ "base" "gaming" ]; };
  firestick = { channel = "stable";   roles = [ "base" "appliance" ]; };
};
```

Glue requirements (read current `flake.nix` fully before writing — pkgs wiring is nuanced):
- `roleSys r = optional (pathExists profiles/${r}/sys.nix) …`, same for `home.nix`.
  Missing halves silently skipped.
- `nixosConfigurations.hwc-<m>` = hardware + one-off config.nix + sys halves of roles +
  HM-as-module wiring of (home halves + one-off home.nix). HM-as-module bootstrap
  (`home-manager.useGlobalPkgs`, `backupFileExtension = "hm-bak"`, `users.eric = …`) moves
  from `profiles/session.nix` into the glue (it is machinery, not menu).
- `homeConfigurations."eric@hwc-<m>"` generated **for every machine in the table** from home
  halves + one-off home.nix. (Today only server+laptop exist — generating all five is an
  additive, accepted change.)
- **Preserve exact pkgs per machine per lane**: server nixosSystem uses `pkgs-stable-cuda`,
  server HM-standalone uses `pkgs-stable`, laptop uses `pkgs-laptop` (unstable+tailscale
  overlay), etc. The table's `channel` maps onto the EXISTING pkgs sets; add an
  `overlayKey`/explicit pkgs field if needed rather than simplifying the overlay story.
  `nixosApiVersion` specialArg per channel is preserved.
- `xps`/`kids`/`firestick` current xps role set inferred from inventory: xps duplicates
  server's couchdb/zfs/sudo/caddy blocks — confirm at execution time that the `server` role
  contents match what xps actually enables; where xps diverges (e.g. exportarr off), the
  divergence stays in `machines/xps/config.nix` as an override, since roles use `mkDefault`.

## 4. What stays in machine files (the canonical one-off list, from the 2026-06-10 inventory)

- **laptop/config.nix**: Sensel lid/acpid quirk (logind + acpid script), Seagate NTFS drive
  (UUID mount + tmpfiles + fixperms), BOM-proof inline `hashedPassword` escape hatch, parked
  ProtonVPN WireGuard stub, firewall port 56037, GPU prime busIDs, NPU/graphics packages,
  thermald disable, `hwc.paths.hot/cold` overrides.
- **laptop/home.nix**: codex `package` pin (callPackage after Phase D moves the derivation),
  n8n MCP accessToken placeholder.
- **xps/config.nix**: DAS import guard (`zfs-import-media-pool` timeout + ConditionPathExists),
  `X11Forwarding = mkForce true`, per-machine disables that override role mkDefaults.
- **server/config.nix**: hostname/hostId/ZFS pools, mounts, Quadro P1000 GPU pin +
  `cudaCapabilities = ["6.1"]`, Hermes Discord `allowedUsers`, jellyfin apiKey literal
  (deferred), legacy youtube dataDir (disabled service), assertion policy block (lines 33-100
  — keep with the machine for now; it asserts machine identity/provenance).
- **All**: `stateVersion`, hardware.nix import, ssh password-auth mkForce (deferred decision).

Everything else in machine files is either a toggle that moves to a role (§5) or misplaced
content logged in the backlog (§10).

## 5. Current → target content mapping

| Source | Destination |
|---|---|
| `profiles/core.nix` | → `base/sys.nix`. SLIM: the ~50-line `hwc.data.backup` defaults block moves to option defaults in `domains/data` (profile keeps only `backup.enable = mkDefault false`). `gatherSys` helper stays here (system-lane aggregation of domains' sys.nix per Law 7). |
| `profiles/session.nix` | → `desktop/sys.nix`, MINUS the `home-manager.users.eric` bootstrap (→ flake glue). The 20-line nix-ld GUI lib list (verbatim dup with gaming.nix) becomes a domain option (suggest `hwc.system.core.guiLibs.enable`) flipped by both desktop and gaming roles. |
| `profiles/home-session.nix` | SPLIT: CLI-shared portion (shell, development, gpg, yazi, tmux?, codex/aider/gemini-cli, herdr, theme defaults that apply headless) → `base/home.nix`. GUI apps (hyprland, waybar, swaync, kitty, thunar, browsers, proton suite, obsidian, office, blender, tuxedo, fonts on) → `desktop/home.nix`. Inline codex mkDerivation → `domains/home/apps/codex/parts/package.nix` (§7.4). The HM 26.05 pin block (gtk4 theme / configType / userDirs) → `desktop/home.nix`. |
| `profiles/monitoring.nix` | SPLIT: observability enables (prometheus, blackbox, cadvisor, grafana, homepage, uptime-kuma, alertmanager+receivers) → `monitoring/sys.nix`. The `hwc.automation.n8n` block incl. secrets wiring and extraEnv (Twilio, Drive folder, PostgREST) → `business/sys.nix`. The gotify-token discovery `let` logic should eventually live inside the n8n module (backlog §10), but for this pass move it verbatim into `business/sys.nix`. `exportarr` → `business`? NO — it is arr-stack metrics → keep in `monitoring/sys.nix` as `mkDefault true`; xps overrides off in its machine file if needed (verify current xps behavior and preserve it). |
| `profiles/gaming.nix` | → `gaming/sys.nix`. REMOVE `imports = [ ./core.nix ]` (machine role list supplies base). Remove dead commented retroarch import block. GUI lib list → shared domain option (see session.nix row). |
| `profiles/firestick.nix` | → `appliance/sys.nix`. Remove `./core.nix` import. Then DELETE the redundant restatements in `machines/firestick/config.nix` (backup mkForce, waitOnline, samba, hardware.monitoring, ssh/tailscale — all duplicate the role). |
| `machines/server/home.nix` mail block (`hwc.mail = {…}`) | → `mail/home.nix` verbatim (accounts, notmuch, calendar, health — preserve-first; it is identity data but only the mail role consumes it). |
| `machines/server/home.nix` CLI enables + `theme.fonts.enable = false` | CLI enables → covered by `base/home.nix`; delete from machine file once equivalent. `theme.fonts.enable = false` STAYS in `machines/server/home.nix` (genuine headless override of base default). |
| `machines/server/config.nix` B-category toggle runs (lines ~107-127, 281-347, 458-609 AI stack, 611-623 couchdb, 660-717, 824-873, 879-1110 media/business/data) | Distribute: business enables → `business/sys.nix`; couchdb + gotify + sudo NOPASSWD + permitCertUid + podman/autoPrune + server firewall level + `hwc.server.*` + packages.server (the server∩xps overlap set, inventory items) → `server/sys.nix`; media/AI enables → `server/sys.nix` for now with `mkDefault` (xps force-disables stay as machine overrides); monitoring source toggles → `monitoring/sys.nix`. Use the cross-machine duplication list (§10.2) as the authoritative "what goes in server role" guide. |
| `machines/xps/config.nix` dup blocks (zfs scrub, couchdb, sudo rules, permitCertUid) | DELETE once `server/sys.nix` covers them (xps gets them via role). |
| `machines/{laptop,kids}` eXoDOS + exogui verbatim dup | NOT a role — it is an app: create `domains/home/apps/exodos/` directory module (index.nix; activation script + desktop entry as parts), enable from `desktop/home.nix`? NO — enable in the two machines' home.nix one-off (laptop + kids) OR in `gaming/home.nix` + laptop one-off. Decide at execution: kids-only + laptop-personal ⇒ simplest correct: module in domains, `exodos.enable = true` in both machines' home.nix. |

Role lane-purity check after mapping: every `home.nix` half contains only HM options
(`hwc.home.*`, `hwc.mail.*`, HM program options); every `sys.nix` half only NixOS options.

## 6. New charter law (draft to include in CHARTER.md as Law 16, version bump v12.0 → v12.1)

> **Law 16: Layer Purity (profiles & machines)**
> - `profiles/<role>/` contains exactly `sys.nix` and/or `home.nix`. Halves contain ONLY
>   option assignments (`mkDefault` for anything a machine may override) and domain imports.
>   Forbidden: `mkDerivation`, `fetchurl`, `writeShellScript*`, inline `systemd.services`
>   bodies, option *declarations*, machine hostnames/names.
> - `profiles/*/home.nix` obeys Law 1 (evaluates with `osConfig = {}`).
> - Roles never import roles. Machine membership lives only in the `flake.nix` machines table.
> - `machines/<m>/` contains `hardware.nix` + one-off `config.nix`/`home.nix`. A machine file
>   line that a second machine of the same kind would copy verbatim belongs in a role or domain.
> - **Lints**:
>   `rg 'mkDerivation|fetchurl|writeShellScript' profiles/` → empty;
>   `rg 'laptop|server|xps|kids|firestick' profiles/` → empty (role named `server/` is exempt
>   from its own name; lint excludes the directory name itself — implement as
>   `rg -i '\b(laptop|xps|kids|firestick|hwc-server)\b' profiles/`);
>   `rg 'import.*profiles/' profiles/` → empty;
>   `rg 'mkOption|mkEnableOption' profiles/` → empty.
> Domain-map table in §2 of the charter gains a note that `profiles/` is the role layer and
> `machines/` the instance layer, governed by this law.

## 7. Home-domain audit fixes (land AFTER the role structure exists; each its own commit)

From the 2026-06-10 four-agent audit. Items renumbered with placement updated for new layout:

1. **Delete `domains/home/apps/n8n/parts/n8n-workflows/`** — 82 MB / 825 tracked files of
   vendored third-party repo, referenced by nothing (Law 13). `git rm -r`. Keep
   `apps/n8n/index.nix` (27-line module) as-is.
2. **Delete `domains/home/apps/aerc/`** (dead duplicate of `domains/mail/aerc/`; contains a
   latent eval crash — unguarded `config.hwc.home.mail.accounts` at index.nix:46 against a
   namespace declared nowhere). Also delete the stale `# add "mail" here` comment in
   `domains/home/index.nix:6` and `git clean` the untracked `domains/home/mail/` .bak tree.
   Verify `rg -n 'apps/aerc|apps\.aerc' domains profiles machines` → nothing enables it.
3. **Inline `apps/tuxedo/options.nix` into its index.nix** under `# OPTIONS` (Law 10
   regression from commit 82e3792b).
4. **Law 3 paths**: `web-build` alias derives from `hwc.paths.nixos` w/ Law-1 fallback
   (`core/shell/index.nix:54`); `apps/transcript-formatter/index.nix:76` WATCH_FOLDER and
   `apps/yazi/parts/keymap.nix:47` `/mnt/media` derive from `hwc.paths.media` w/ fallback.
   Note: yazi + shell are live on the SERVER — behavior must be identical there.
5. **`systemd.user.startServices = "sd-switch"` → `profiles/base/home.nix`** (reaches all
   machines — this placement is the point of the refactor). Remove the stray copy in
   `apps/transcript-formatter/index.nix:84` and the `restartWaybar` activation hack
   (`apps/waybar/index.nix:69-71`). ⚠ DELIBERATE BEHAVIOR CHANGE: user units (incl. server
   mail timers) restart on switch. Flag in commit message.
6. **Theme honesty pass**:
   a. Declare the phantom options consumers already read — `hwc.home.theme.{cursor, icons,
      gtkTheme, typography}` (consumed by `templates/gtk.nix`, `hyprland/parts/session.nix`)
      — sourced from the palette files; wire `deep-nord.nix`'s existing cursor block through.
   b. Fix `neomutt/parts/theme.nix:12` to key off `theme.palette` (not undeclared
      `theme.name`).
   c. `waybar/parts/theme.nix` is imported-but-unused: finish the migration — feed its CSS
      variables into `parts/appearance.nix` and replace the 66 hardcoded hexes; if that
      proves too entangled, delete theme.nix + the import and log the de-hardcode as backlog.
   d. De-hardcode fzf + starship colors in `core/shell/index.nix` (~191-194, ~455-507) via
      `theme.colors` (⚠ visible color change on server shell: hardcoded Gruvbox → hwc
      palette; accepted).
   e. De-hardcode calcure/calcurse Nord hexes via theme.colors.
   f. Standardize theme access on the guarded read `(config.hwc.home.theme or {}).colors or {}`;
      migrate the unguarded readers (tmux, swaync, waybar, hyprland/parts/theme.nix) and the
      direct palette-file importers (neomutt, librewolf).
   g. swaync font: requests "JetBrainsMono Nerd Font", not installed — switch to an installed
      font token or add the package; prefer adding `theme.fonts.mono/ui` tokens and consuming
      them in kitty/waybar/swaync.
   h. Delete dead `theme/index.nix:66` assertion line + stale adapters comments/headers;
      `qt = { enable = true; platformTheme.name = "gtk3"; }` added to theme module (Qt apps
      follow GTK dark).
7. **HM correctness fixes**:
   a. freecad activation dry-run bug (`apps/freecad/index.nix:84-121`): heredoc-redirect
      escapes `$DRY_RUN_CMD` — convert to `pkgs.writeText` + `run install -m644` (thunar
      seed-once pattern).
   b. `run`-prefix unguarded activation commands: `core/xdg-dirs.nix:46`,
      `apps/tuxedo/index.nix:49-58`, `apps/dt/index.nix:211-214`, (aerc deleted by 7.2).
   c. Move inline codex derivation → `apps/codex/parts/package.nix`; laptop pins it via
      `codex.package = pkgs.callPackage … {}` in `machines/laptop/home.nix` one-off.
      ⚠ Do NOT make it the module default — server intentionally uses stock `pkgs.codex`
      (stable). Add `meta.mainProgram`.
   d. Remove duplicate tmux surface `hwc.home.shell.tmux` (`core/shell/index.nix:98-101,
      516-522`) in favor of `apps/tmux/`. Verify nothing sets `shell.tmux.*` first.
   e. Inert `programs.bash.initExtra` in `apps/aider/index.nix:117` +
      `apps/gemini-cli/index.nix:30` (bash never enabled — secret sourcing silently dead in
      bash): drop the bash branches (zsh branches already work).
   f. `GPG_TTY` from `home.sessionVariables` (`apps/gpg/index.nix:34`) → zsh initContent
      `export GPG_TTY=$(tty)`.
   g. `xdg.mimeApps` browser defaults in librewolf module: `x-scheme-handler/http`, `https`,
      `text/html` → `librewolf.desktop`. Remove invalid `"text/*"`/`"application/x-*"` globs
      (`apps/thunar/index.nix:84-85`).
   h. Betterbird prefs.js hazard (`parts/profile.nix:410-415`, runtime-rewritten file under
      home.file): module is enabled nowhere — do NOT invest in a rewrite now; move the three
      prefs blocks into the existing user.js channel if trivial, otherwise add a loud
      `# HWC-WARNING` comment + backlog entry, and delete the dead
      `lib.mkIf (profile ? activation)` guard (`index.nix:68-70`).
8. **Law 2 namespace fix**: `hwc.home.shell.*` → `hwc.home.core.shell.*` and
   `hwc.home.development.*` → `hwc.home.core.development.*` (folders demand it; "no
   exceptions ever" law). Update ALL reference sites — after this refactor they are:
   `profiles/base/home.nix`, `machines/*/home.nix`, `core/development/index.nix` nvim bridge,
   any `rg 'hwc\.home\.(shell|development)'` hit incl. shell scripts/docs. Single commit.
9. **Structural cleanups** (one commit, no behavior change): split `core/shell/index.nix`
   (605 lines) into parts/ (aliases, ssh, zsh-init, prompt, fzf — follow betterbird/waybar
   precedent); add `mkSimpleApp` helper in `domains/lib/` and collapse the ~13 identical
   one-package modules (obsidian, slack, localsend, ipcalc, markitdown, wasistlos,
   xournalpp, qbittorrent, bottles-unwrapped, google-cloud-sdk, imv, opencode,
   onlyoffice-desktopeditors) — helper must preserve Law 2 (namespace from folder) and Law 6
   shape; add `hwc.lib` helper for the duplicated `isNixOSHost`/cross-lane assertion
   boilerplate (7 modules); delete stale scaffolding (`hyprland-new` exclusion, `.bak.nix`
   filter, `modules/home/` headers, empty placeholder sys.nix×3, `apps/nvim/parts/lua/.luarc.json`,
   `machines/laptop/home.bak`, qutebrowser scaffold TODO fleshed or left but de-TODO'd).
10. **Docs**: rewrite `domains/home/README.md` (Law 12 sections: Purpose/Boundaries/
    Structure/Changelog; real layout — no `environment/`; real app list (53 − deletions);
    remove wayvnc ghost; document the canonical theme accessor). Fix `theme/README.md`
    (describe real architecture, not phantom adapters), `core/README.md` Structure,
    `domains/business/README.md` (currently contains the AI-MCP readme by mistake). Per-commit
    README changelog updates throughout per Law 12.

## 8. Execution order, commits, verification

**Doctrine**: preserve-first; commit BEFORE every build; never `git add -A`; one commit per
step below; update touched domain READMEs (Structure + Changelog) in the same commit;
state HM-only vs system per rebuild. `nix flake check` before starting and after each phase.

**Baseline (Phase 0)**: commit any WIP. Record baseline drv hashes:
`nix build .#nixosConfigurations.hwc-<m>.config.system.build.toplevel --dry-run` for all 5;
`nix build .#homeConfigurations."eric@hwc-{server,laptop}".activationPackage --dry-run`.
Save outputs to `workspace/plans/rolls-baseline-<date>.txt` for comparison.

**Phase A — roles by pure relocation** (target: drv hashes UNCHANGED for all machines):
A1 create `profiles/{base,desktop,monitoring,gaming,appliance}/` from existing files per §5
   (moves + the import removals compensated by updating the 5 machines' import lists in
   place — machines temporarily import role halves explicitly). home-session split into
   base/home + desktop/home. server/business roles NOT yet created.
A2 verify hashes unchanged (the gaming/firestick core-import removal must be offset by
   machines importing base — firestick/kids configs updated same commit).

**Phase B — flake table + glue**:
B1 add machines table + resolver; nixosConfigurations/homeConfigurations generated; machines'
   explicit profile imports removed. HM bootstrap moves to glue.
B2 verify: all 5 toplevels + 5 homeConfigurations eval; server/laptop hashes unchanged vs
   baseline (xps/kids/firestick may differ ONLY by the new standalone homeConfigurations
   existing — toplevels must match).

**Phase C — server/business extraction** (hash-neutral intent, verify per commit):
C1 `server/sys.nix` from the server∩xps overlap set (§10.2 list); xps dups deleted same commit.
C2 `business/sys.nix` from server business/automation toggles + monitoring.nix n8n block;
   `monitoring/sys.nix` keeps observability only.
C3 `mail/home.nix` from server home.nix; base/home covers server CLI enables; server
   machine files shrink to §4 one-offs.
C4 firestick machine-file dedup vs appliance role.

**Phase D — home-domain fixes**: §7 items 1-8, each its own commit, in that order. Items
touching live server config (4, 5, 6d, 8) note "server rebuild required" in the commit body.

**Phase E — structure + docs + charter**: §7 items 9-10, Law 16 into CHARTER.md (v12.1 +
version-history entry + lints added to §3.1), README sweeps.

**Activation** (after each of D's behavior-changing commits and at the end): run `hostname`
first; laptop: `sudo nixos-rebuild switch --flake .#hwc-laptop` for system/mixed,
`hms` for HM-only; server: rebuild ON the server (`hms` for HM-only items 4/5/6d).
Other machines apply on their next rebuild — note in final report which machines have
pending changes. NEVER report done after `nix build` alone.

**Definition of done**: all §6 lints empty; charter §3.1 home-domain lints empty
(tuxedo options.nix gone, Law 3 home hits gone); all 5 toplevels build; 5 standalone
homeConfigurations eval; laptop + server switched live; READMEs current; baseline-diff
report written to `workspace/plans/roles-refactor-report.md`.

## 9. Standing findings registry (carry into the report; do not fix unless listed above)

- Plaintext Jellyfin API key `machines/server/config.nix:937` — DEFERRED by Eric (rotate+agenix later).
- SSH password-auth policy contradiction (core vs server/laptop/xps mkForce) — DEFERRED.
- `machines/hwc-{laptop,server,xps}/` dirs contain only AGE_PUBLIC_KEY.txt parallel to real
  machine dirs (xps has the key in BOTH places) — consolidate during Phase B if trivial
  (keys referenced by secrets generator — check `domains/secrets/parts/lib.nix` first),
  else log.
- xps swapfile defined in both hardware.nix:60-63 and config.nix:65 — dedupe in Phase C.
- server: `hwc.monitoring.alerts.sources.smartd` AND raw `services.smartd` both configured —
  overlapping ownership; log, don't touch.
- server logrotate for docker containers while docker is force-disabled — delete in Phase C
  (dead config, zero risk).
- `apps/gemini-cli` deep `osCfg.age.secrets…` access pattern is safe but outside Law 1's
  three whitelisted patterns — log for a charter clarification, don't churn.

## 10. Backlog (explicitly NOT in this plan's scope — log in report)

### 10.1 C-category content still in machine files after Phase C (~400 lines)
server: inline Borg preBackupScript (32-line pg_dumpall/CouchDB shell) → data domain;
45-line firewall port registry → derive from domains; syncthing folder map (dup w/ laptop)
→ shared data; cloudflared ingress table → networking routes registry; sysctl/udev tuning →
system domain; gotify token discovery logic → into n8n module. laptop: TLP body (+ xps's) →
system domain option set; perf-mode/balanced-mode writeShellScriptBins → domains/system
(file's own TODO says so); NFS client mount w/ hardcoded Tailscale IP → paths/networking;
static networking.hosts map → derive from routes.nix; acpid lid script half → co-locate with
waybar lid-toggle domain part. kids: retroarch core list ↔ `hwc.gaming.retroarch.cores`
reconciliation.

### 10.2 Reference: server∩xps overlap set (the `server/sys.nix` seed list)
zfs autoScrub/trim; CouchDB block; sudo NOPASSWD (podman/systemctl/journalctl); caddy
permitCertUid; server firewall level; `hwc.server.*` enables; packages.server; gotify server;
podman runtime + autoPrune; CUDA cache settings (server+laptop — goes to base or a `cuda`
flag, decide at execution).

### 10.3 Other
`workspace/home/mail/` missing from home README workspace list; `apps/analysis` sys.nix
no-op + never-enabled option; 7 imported-never-enabled apps (betterbird, jellyfin-media-player,
mpv, qutebrowser, thunderbird, transcript-formatter — post-deletion of aerc) — Eric to decide
keep/delete per app later; betterbird→programs.thunderbird migration if ever reactivated;
`exportarr` placement sanity-check once media roles are revisited.
