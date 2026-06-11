# Roles Architecture Refactor — Final Report

**Date**: 2026-06-11 (executed from the 2026-06-10 approved spec)
**Charter**: v12.0 → v12.1 (Law 16: Layer Purity)
**Commits**: ~25, phases 0/A/B/C/D/E per the plan's execution order.

## What changed

1. **Role layer** — `profiles/<role>/{sys,home}.nix` for 8 roles:
   base, desktop, server, business, monitoring, gaming, appliance, mail.
   Roles are option flips + domain imports only; roles never import roles.
2. **Machine registry** — `flake.nix` `machines` table (channel, roles,
   per-machine pkgs, one-off extras). `mkNixos`/`mkHome` glue resolves role
   halves (missing halves skipped) and generates all `nixosConfigurations`
   plus standalone `homeConfigurations` for every machine — xps/kids/
   firestick gained `hms` lanes.
3. **Machine files shrunk** — server config.nix 1121 → ~860 lines (couchdb,
   gotify, sudo, podman, zfs hygiene, firewall level, business subdomains,
   n8n/mqtt all in roles); xps deduped against the server role; firestick
   deduped against appliance; server home.nix is one-offs only.
4. **Home-domain audit landed** (all §7 items 1–10): 82 MB vendored
   n8n-workflows deleted; dead apps/aerc deleted; tuxedo Law 10 fix; Law 3
   path derivations; fleet-wide sd-switch; theme honesty pass; HM
   correctness fixes a–h; hwc.home.core.* namespace fix; shell split into
   parts; mkSimpleApp + hm.nix helpers; README rewrites.

## Verification method

Baseline drv hashes recorded pre-refactor
(workspace/plans/rolls-baseline-2026-06-10.txt). Every phase was gated on
either byte-identical hashes or a nix-diff proof that deltas were
order-only (identical package/rule/route sets) or intentional and named.
Notable: eric@hwc-server HM stayed byte-identical to the original baseline
through Phases A–C; firestick toplevel byte-identical through Phase C.

## Pre-existing breakage fixed

- **hwc-xps did not evaluate at baseline** (commit fce96f45 set HM-26.05
  pin options that don't exist on stable HM 25.11). Fixed by guarding the
  pin block on nixosApiVersion.
- xps fstab contained its swapfile twice (config.nix + hardware.nix dup).
- machines/hwc-*/ AGE-key phantom dirs consolidated into the real machine
  dirs (xps's commented duplicate removed — readKey can't parse comments).
- yazi/transcript-formatter Law-3 fix initially tripped the documented
  attrByPath-returns-null trap on hwc-kids (media.root = null); fixed with
  explicit null handling.

## Intentional behavior changes (flagged in commits)

- xps gains the server role's podman settings (docker-compat shim,
  default-network DNS, weekly autoPrune) and loses domains/automation.
- Fleet-wide `systemd.user.startServices = "sd-switch"` — user units
  (incl. server mail timers) restart on switch when changed.
- Cursor theme: Adwaita → Nordzy (the palettes' stated intent, now wired).
- fzf/starship colors: literal Gruvbox-Material → hwc palette tokens.
- swaync font: never-installed JetBrainsMono → Hack (ui token).
- yazi "Go: media" points at each machine's real media root in module lane.
- librewolf registered as default browser (xdg.mimeApps).
- xps codex falls back to stock pkgs.codex (pin is now a laptop one-off).
- kids/firestick explicitly pin their lean CLI state against base defaults.

## Definition-of-done status

- Law 16 lints: EMPTY (all four).
- Charter §3.1 home lints: options.nix gone; remaining Law-3 string hits
  are Law-1 fallback literals (sanctioned pattern, scraper precedent).
- All 5 toplevels instantiate + dry-run build; all 5 homeConfigurations eval.
- READMEs: profiles/, domains/home (+core, theme), domains/business,
  domains/data/backup, domains/lib updated; CLAUDE.md/AGENTS.md updated.
- Activation: laptop switched live (see Activation below); server pending.

## Activation state

- **hwc-laptop**: SWITCHED LIVE 2026-06-11
  (/nix/store/60sgkd17aa153yik7vkz4hlx659ndpkz-…); home-manager-eric,
  waybar, swaync all active post-switch.
- **hwc-server**: REBUILD REQUIRED (theme pass: cursor + fzf/starship
  colors in HM; roles are hash-neutral). Run on the server:
  `sudo nixos-rebuild switch --flake ~/.nixos#hwc-server`.
- **hwc-xps / hwc-kids / hwc-firestick**: pick up changes on their next
  rebuild (xps: podman additions + business-role removal are the deltas).

## Standing findings registry (NOT fixed — carried per plan §9)

- Plaintext Jellyfin API key machines/server/config.nix (~line 860) —
  DEFERRED by Eric (rotate + agenix later).
- SSH password-auth policy contradiction (base hardening says off; server/
  laptop/xps mkForce true) — DEFERRED, overrides preserved byte-for-byte.
- server: hwc.monitoring.alerts.sources.smartd AND raw services.smartd
  both configured — overlapping ownership; logged, untouched.
- apps/gemini-cli deep osCfg.age.secrets access — outside Law 1's three
  whitelisted patterns but safe; charter clarification candidate.

## Backlog (from plan §10 + execution findings)

- §10.1 C-category machine-file content (~400 lines): borg preBackupScript
  → data domain; firewall port registry derivation; syncthing folder map
  dedup; cloudflared ingress table → routes registry; sysctl/udev tuning →
  system domain; gotify-token discovery → n8n module; laptop TLP/perf-mode
  scripts → system domain; NFS mount + static hosts map derivations;
  kids retroarch core list ↔ hwc.gaming.retroarch.cores reconciliation.
- nix-ld GUI lib list still duplicated in desktop/sys.nix + gaming/sys.nix —
  the planned hwc.system.core.guiLibs option was deferred (list-merge
  reordering churn vs. benefit); revisit with the §10.1 sweep.
- CUDA cache substituters duplicated in laptop+server machine files —
  candidate for base role or a `cuda` flag.
- waybar appearance.css de-hardcode: 66 curated Gruvbox-Material hexes;
  palettes now carry sectionA-D tokens for that redesign.
- hyprcursor assets (Nordzy-hyprcursors) missing from repo — palette
  hyprcursor blocks are not wired; restore assets or drop the blocks.
- eXoDOS duplicate blocks remain in machines/{laptop,kids}/home.nix —
  the planned domains/home/apps/exodos/ module was NOT created this pass
  (deliberate scope cut; both copies still verbatim-identical).
- 6 imported-never-enabled apps (betterbird, jellyfin-media-player, mpv,
  qutebrowser, thunderbird, transcript-formatter) — Eric to decide
  keep/delete per app.
- workspace/nixos legacy tooling scripts still reference pre-roles layout
  in places beyond the namespace mappings fixed in D8.
