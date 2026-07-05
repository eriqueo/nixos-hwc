# HWC Architecture Charter v12.2

**Owner**: Eric
**Scope**: `nixos-hwc/` — all machines, domains, profiles, Home Manager, and supporting files
**Goal**: Deterministic, maintainable, reproducible NixOS configuration via strict domain separation, explicit APIs, and mechanical enforcement.
**Philosophy**: This document defines **enforceable architectural laws**. Implementation details and domain-specific guidance live in domain READMEs (Law 12). A law that cannot be checked mechanically is a guideline and is labeled as such. A law that references infrastructure that does not exist is a bug in the charter.
**Last revised**: 2026-07-05

---

## 0. Doctrine

1. **Preserve-first**: refactor = reorganize, never rewrite. 100% feature parity through migrations.
2. **Temporary means tracked**: every wrapper, alias, pin, or migration shim carries an in-code annotation (§4) stating its removal condition. An untracked "temporary" thing is permanent cruft.
3. **Never switch on a failing build.** Commit before rebuild.
4. **Migrations finish.** A version-history entry claiming a migration is complete must be true (`v11.0` claimed `options.nix` elimination; 16 files remained for three months). Declare completion only after the relevant lint passes.

---

## 1. Architectural Laws

Each law states: the rule, the violation, and (where it exists) the mechanical check. Checks live in §3 and should be wired into `nix flake check` (§3.3).

### Law 1: Handshake Protocol (HM standalone compatibility)

Home-lane modules **must** evaluate cleanly on non-NixOS hosts.

Required signature and guard:
```nix
{ config, lib, pkgs, osConfig ? {}, ... }:
let isNixOS = osConfig ? hwc;
```

Permitted access patterns — **only** these:
```nix
assertions = lib.mkIf isNixOS [ ... ];                     # guard
let osHwc = osConfig.hwc or {}; in osHwc.paths.media or "/fallback";  # namespace fallback
lib.attrByPath ["hwc" "paths" "media"] "/fallback" osConfig;          # deep access
```

Forbidden: `osConfig.hwc.x or null` (crashes when `osConfig = {}`), any unguarded deep access.

**Violation**: any `osConfig` access outside the three patterns.

### Law 2: Strict Namespace Fidelity

Option namespace **must exactly match** the folder path. No shortcuts, no aliases.

`domains/home/apps/firefox/` → `hwc.home.apps.firefox.*`
`domains/networking/` → `hwc.networking.*`
`domains/paths/` → `hwc.paths.*`

Every top-level directory under `domains/` is a domain and owns the namespace of the same name (§2 is the authoritative list). A namespace is invalid only if its folder does not exist.

**Violation**: namespaces with no corresponding folder (`hwc.services.*`, `hwc.features.*`, `hwc.alerts.*`, `hwc.infrastructure.*`) or folder paths abbreviated in the namespace.

> v12 note: prior versions listed `hwc.networking` as a violation while `domains/networking/` existed and used it. The folder is real; the namespace is valid. The law is the mapping, not a blessed list.

### Law 3: Path Abstraction Contract

No filesystem paths hardcoded outside `domains/paths/paths.nix`.

```nix
volumes = [ "${config.hwc.paths.media.music}:/music:ro" ];   # correct
volumes = [ "/mnt/media/music:/music:ro" ];                  # violation
```

`paths.nix` guarantees: user/home auto-detection, defaults for all storage tiers, absolute-path assertions, no `null` defaults (machines override). Law-1-style fallbacks (`osHwc.paths.media or "/fallback"`) are compliant — the fallback literal is the documented escape hatch for standalone HM, not a hardcoded path.

**Violation**: literal `/mnt/`, `/home/eric/`, `/opt/` in any `.nix` outside `domains/paths/` (docs excluded).

### Law 4: Unified Permission Model

All services run as primary user **UID 1000 : `users` GID 100**.

Containers: `PUID = "1000"; PGID = "100";` (PGID 1000 is the canonical recurring bug).
Native services:
```nix
serviceConfig = {
  User = lib.mkForce "eric";
  Group = "users";
  StateDirectory = "hwc/<service>";
};
```
Secrets mounts: `mode = "0440"; owner = "root"; group = "secrets";` and consuming service users include `extraGroups = [ "secrets" ]`.

**Secrets are generated, not declared**: `domains/secrets/parts/lib.nix` (pure-`builtins` generator) walks `parts/**.age` and emits recipients + mounts. The pattern above is the generator's default; per-name exceptions go in `declarations/generated.nix` (`mountOverrides`). Add a secret = drop `<name>.age` into `parts/<category>/` + `sudo agenix -r`. Do **not** reintroduce per-secret declaration files. See `domains/secrets/README.md`.

**Violation**: PGID=1000; secrets without 0440/secrets-group; hand-written `age.secrets` mounts outside the generator (except the four `caddy/` certs — documented exception, runtime hostname selection).

> v12 note: the `hwc.system.identity.*` option set promised by v11 was never implemented. Literal `1000`/`100`/`"eric"`/`"users"` with this law cited in a comment **is** the standard, not a fallback. If identity options land later, this law gets a version bump.

### Law 5: Container Standard (mkContainer)

All OCI containers use the `mkContainer` helper (`domains/lib/mkContainer.nix`) unless a justification comment explains why not. Guarantees: PUID/PGID per Law 4, host TZ, health-check pattern, minimal privileges.

**Violation**: raw `virtualisation.oci-containers.containers` blocks without a `# HWC-EXCEPTION(Law 5)` comment.

### Law 6: Unified Module Structure

Every directory module's `index.nix` contains, in order:

```nix
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.<namespace>;
  # HELPERS (optional) — pure imports from ./parts/, clearly labeled
in
{
  # OPTIONS
  options.hwc.<namespace> = { enable = lib.mkEnableOption "..."; ... };

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
    ...
    # VALIDATION — assertions INSIDE the mkIf block
    assertions = [ ... ];
  };
}
```

Cross-cutting assertions live in the nearest parent `index.nix`, at most one level up, guarded by the enabling options.

**Violation**: missing/ordered-wrong sections, assertions outside the `mkIf`, unlabeled helpers.

### Law 7: sys.nix Lane Purity

Co-located `sys.nix` files in home domains belong exclusively to the system lane: they declare `hwc.system.apps.<name>.*`, are imported only by system profiles, and home `index.nix` never imports them. System config never depends on home options (Law 11). A `sys.nix` must sit beside the `index.nix` it supports — an orphaned options-declaring `sys.nix` with no sibling `index.nix` is a shape violation (Law 9).

**Violation**: home→sys import, system→home dependency, `sys.nix` reading `hwc.home.*`, orphaned `sys.nix`.

### Law 8: Data Retention Contract

Every persistent data store declares its retention in Nix: application-level retention config **plus** a fail-safe cleanup timer, and a classification comment — `CRITICAL` (indefinite + backed up), `REPLACEABLE` (indefinite, not backed up), `AUTO-MANAGED` (time/size-limited).

**Violation**: persistent volume or StateDirectory without documented retention + timer.

### Law 9: Module Shape Discipline

- **Leaf module** = one `.nix` file, implementation only, **never** declares `hwc.*` options.
- **Directory module** = `index.nix` (+ optional `parts/`, `sys.nix`); required as soon as the module declares options or manages payload (generated files, dotfiles, helpers).

Litmus: declares any `hwc.*` option → directory. Only sets packages/programs/services with no payload → leaf.

**Violation**: leaf declaring options; directory with no namespace or payload to justify it; separate `options.nix` files (see Law 10).

### Law 10: Option Declaration Locality

`mkOption`/`mkEnableOption` appear **only** in:
- `index.nix` (standard location, under `# OPTIONS`),
- `sys.nix` (only `hwc.system.apps.*`, per Law 7),
- `domains/paths/paths.nix` (the single primitive-module exception; carries its own justifying header).

Separate `options.nix` files are forbidden — the v11.0 migration eliminated the pattern; the 18 stragglers found in the 2026-06-09 audit were inlined the same day (lint now returns zero).

**Tracked violations (burn-down list, not precedent)**: 2 files remain as of 2026-07-05 (`domains/system/mcp/parts/jt.nix`, `domains/secrets/declarations/caddy.nix`) — the v12.1 text claimed ~21; the migration is essentially complete. List: `rg -l 'mkOption' domains --type nix -g '!**/index.nix' -g '!domains/paths/paths.nix' -g '!**/sys.nix'`.

**Violation**: `mkOption` anywhere else, including `parts/*.nix`.

### Law 11: Domain Evaluation Order

```
paths → lib → system → home → [service domains] → secrets
```

Service domains (§2) may depend on each other (no cycles) and on paths/lib/system/home. Reverse dependencies are forbidden (e.g., system reading media options).

**Violation**: cycles or reverse dependencies.

### Law 12: Domain Documentation Contract

Every domain and subdomain has a `README.md` with, in order: `## Purpose` (1–3 sentences), `## Boundaries` (✅ manages / ❌ does not → redirects), `## Structure`, `## Changelog` (newest first, one line per change, prunable after 6 months).

A commit touching a domain updates that README's Structure + Changelog. Enforcement: pre-commit hook and the `/cp`–commit workflow. (No automation tool is currently implemented; if one lands, it gets named here in a version bump — the charter does not reference tools that do not exist.)

**Violation**: missing README/section, changelog older than the last structural commit.

### Law 13: Repository Hygiene (new in v12)

The repo is a **configuration** repo. Tracked content is Nix, source code, docs, and encrypted secrets — nothing else.

- Never commit: binaries (APKs, wheels, packet captures), `node_modules/`, `dist/`/build output, scratch `tmp/` dirs, media assets that belong to a deployed site's own pipeline.
- Untracked build artifacts may exist transiently in app `src/` dirs (npm workflows) but a directory containing **only** artifacts (no source) is cruft and gets deleted.
- Vendored third-party blobs require a `# HWC-EXCEPTION(Law 13)` annotation with a removal condition.

**Violation**: any tracked file >2 MB that is not an encrypted secret or documentation image; artifact-only directories.

### Law 14: Flake Input Discipline (new in v12)

- Every input in `flake.nix` is consumed by an output. Unconsumed inputs are deleted.
- Every **pin** (commit-pinned nixpkgs, version-pinned package input) carries a comment with the reason **and the removal condition** ("remove when channel tailscale ≥ 1.98.2"). At each `nix flake update`, removal conditions are checked.
- No input may reference this repository itself.
- Two inputs resolving identically (same URL/ref) are one input.

**Violation**: unconsumed inputs, pins without removal conditions, self-references, duplicate-resolution inputs.

### Law 15: Runtime Hygiene (new in v12)

State that grows must have a declared bound, in Nix:

- **Container images**: `virtualisation.podman.autoPrune` enabled; images pinned to tags or digests, not floating `:latest`, so upgrades are git diffs.
- **Generations / store**: `nix.gc` with explicit `--delete-older-than`; `auto-optimise-store` on.
- **Journals**: `SystemMaxUse` set.
- **Dumps/exports**: compressed at creation, rotated by timer (Law 8), long-term retention delegated to borg.
- Exactly **one** mechanism per backup concern — duplicate ad-hoc scripts for the same data are violations.

**Violation**: unbounded growth surfaces; duplicate backup writers; floating image tags without justification.

### Law 16: Layer Purity (profiles & machines) (new in v12.1)

The repo has three layers: **domains** (capabilities), **profiles** (roles),
**machines** (instances). Profiles and machines now have a contract too:

- `profiles/<role>/` contains exactly `sys.nix` (NixOS lane) and/or
  `home.nix` (HM lane). A half with nothing to say does not exist. Halves
  contain ONLY option assignments (`mkDefault` for anything a machine may
  override) and domain imports. Forbidden: `mkDerivation`, `fetchurl`,
  `writeShellScript*`, inline `systemd.services` bodies, option
  *declarations*, machine hostnames/names.
- `profiles/*/home.nix` obeys Law 1 (evaluates with `osConfig = {}`).
- Roles never import roles. Machine membership lives only in the
  `flake.nix` machines table — the single source of truth for the fleet
  (channel, role list, per-machine pkgs).
- `machines/<m>/` contains `hardware.nix` + one-off `config.nix`/`home.nix`.
  A machine-file line that a second machine of the same kind would copy
  verbatim belongs in a role or domain.

**Violation**: derivations/option declarations in profiles, role-to-role
imports, machine names inside profiles, role membership wired anywhere but
the flake machines table.

---

## 2. Domain Map (authoritative — must match `ls domains/`)

| Domain | Boundary | Never contains |
|---|---|---|
| `paths/` | all filesystem paths, storage tiers, user-home detection | service config, dotfiles |
| `lib/` | pure helpers (`mkContainer`, `mkInfraContainer`, `arr-config`) | options, config assignments |
| `system/` | accounts, networking core, security, OS packages, GPU, storage, virtualization, MCP system services | HM configs, secret declarations |
| `home/` | HM apps, DE/WM, dotfiles; dual activation (HM-as-module via `nixos-rebuild`, HM-as-flake via `hms`); `sys.nix` co-location per Law 7 | `systemd.services`, `environment.systemPackages` (outside `sys.nix`) |
| `secrets/` | generated agenix recipients/mounts, encrypted `.age` payloads | plaintext values, hand-written per-secret declarations |
| `ai/` | ollama, open-webui, AI routing, AI CLI tooling | HM configs |
| `automation/` | n8n, scheduled workflows | HM configs |
| `business/` | Heartwood CMS/site, estimator, leads, morning-briefing | personal configs |
| `data/` | borg backups, storage policies, databases | service configs |
| `gaming/` | retroarch, steam, game servers | media server config |
| `mail/` | aerc, protonmail-bridge, mbsync, notmuch pipeline | unrelated notification routing |
| `media/` | jellyfin, *arr, frigate, immich, downloaders | HM configs |
| `monitoring/` | prometheus, grafana, alertmanager, exporters | alert *delivery* (→ notifications) |
| `networking/` | Caddy reverse proxy + ALL routes, VPN/gluetun, tailscale, podman networks | HM configs |
| `notifications/` | hwc-notify dispatcher, gotify, channels/routing data | metric collection (→ monitoring) |
| `server/` | server-native AI services (hermes, llama-cpp, lead-scout, …), container gateway pieces | HM configs |

Boundary rule of thumb: **monitoring decides *when* to alert; notifications decides *how* it reaches you.**

Changes to this table (add/remove/rename a domain) are normative charter changes: version bump + README.

Layer note (v12.1): `domains/` is the capability layer; `profiles/` is the
**role layer** (one folder per role, `sys.nix`/`home.nix` lane halves);
`machines/` is the **instance layer** (hardware + genuine one-offs). Both
are governed by Law 16; membership lives in the `flake.nix` machines table.

---

## 3. Mechanical Validation Suite

### 3.1 Lints (must return empty)

```bash
# Law 1 — osConfig safety
# (v12.2 fix: whitelist generalized — any `osConfig ? x` guard and any `osConfig.<path> or <fallback>`
#  is crash-safe with osConfig = {}; the old whitelist only accepted the hwc-specific spellings)
rg 'osConfig\.' domains/home --type nix | rg -v 'osConfig\.[a-zA-Z0-9_.]+ or |attrByPath|osConfig \?|lib\.mkIf isNixOS|#'

# Law 2 — phantom namespaces (folders that don't exist)
rg 'hwc\.(services|features|alerts|infrastructure)\.' domains --type nix

# Law 3 — hardcoded paths
rg '"/mnt/|"/home/eric/|"/opt/' domains --type nix --glob '!domains/paths/**' --glob '!*.md'

# Law 4 — permission model (anchored to the assigned value, not prose/comments)
rg 'PGID\s*=\s*"?1000"?\s*;' domains --type nix
./workspace/utilities/lints/permission-lint.sh

# Law 5 — raw container blocks
# (v12.2 fix: `rg -L` means --follow, not files-without-match; the old lint always passed vacuously)
rg 'oci-containers\.containers\.' domains --glob '!**/mkContainer.nix' -l | xargs -r rg --files-without-match 'HWC-EXCEPTION\(Law 5\)'

# Law 7 — lane purity
rg 'import.*sys\.nix' domains/home/*/index.nix

# Law 10 — option locality (separate options.nix forbidden)
fd options.nix domains
rg 'mkOption' domains --type nix --glob '!**/index.nix' --glob '!domains/paths/paths.nix' --glob '!**/sys.nix'

# Law 12 — README presence + sections
for d in domains/*/; do [ -f "$d/README.md" ] || echo "Missing: $d/README.md"; done
# (v12.2 fix: same -L bug as Law 5 — check each required section's absence explicitly)
for s in Purpose Boundaries Structure Changelog; do rg --files-without-match "^## $s" domains/*/README.md; done

# Law 13 — repo hygiene
git ls-files | xargs -I{} du -k "{}" 2>/dev/null | awk '$1>2048' | rg -v '\.age|docs/.*\.(png|jpg)'

# Law 14 — flake self-reference / duplicate inputs
rg 'github:eriqueo/nixos-hwc' flake.nix

# Law 16 — layer purity (profiles & machines)
rg 'mkDerivation|fetchurl|writeShellScript' profiles/ --glob '!README.md'
rg -i '\b(laptop|xps|kids|firestick|hwc-server)\b' profiles/ --glob '!README.md'
rg 'import.*profiles/' profiles/
rg 'mkOption|mkEnableOption' profiles/

# Cross-module: duplicate systemd service definitions
rg -o 'systemd\.services\.[a-zA-Z0-9_-]+' domains -r '$0' --no-filename | sort | uniq -d
```

### 3.2 Eval/build-time validations
- Path absoluteness/non-null: assertions in `domains/paths/paths.nix`
- Container PUID/PGID: defaults in `mkContainer`
- Inter-module dependencies: VALIDATION sections (Law 6)

### 3.3 Target state: `nix flake check` as the enforcement gate
Wrap each §3.1 lint in a `pkgs.runCommand` exposed under `checks.x86_64-linux.charter-law<N>`, so the entire charter is enforced by `nix flake check` locally and in CI. Until this lands, §3.1 is run manually before structural commits.

---

## 4. Exception Annotation Protocol

```nix
# HWC-EXCEPTION(Law X): <brief reason>
# Justification: <detail>
# Plan: <removal condition, link to workspace/plans/, or "permanent by design">
# Revocable: <yes/no>
```

Current standing exceptions:
- **Law 10**: `domains/paths/paths.nix` primitive module (permanent by design).
- **Law 4**: four hand-written `caddy/` cert declarations (runtime hostname selection).

No exceptions ever: **Law 2** (namespace fidelity).

Every exception requires: in-code annotation, removal condition when temporary, lint allowlist entry where applicable.

## 5. Enforcement Levels

| Severity | Meaning | Action |
|---|---|---|
| Critical | build failure / runtime breakage | fix immediately |
| High | charter law violation | fix before next major work |
| Medium | deprecated pattern / inconsistency | track in backlog |
| Low | docs/style nit | optional |

## 6. Change Management & Version History

- Normative changes (laws, domain map) require: lint pass, affected README review, version bump.
- Proposals in `workspace/plans/`.
- A version entry may claim a migration complete **only after its lint passes** (Doctrine §0.4).

**Version History** (excerpt):
- **v12.2 (2026-07-05)**: Lint repair pass from the 2026-07-05 systems audit (`workspace/plans/2026-07-05-systems-process-audit.md`). Fixed two vacuously-passing lints (Laws 5 & 12 used `rg -L`, which is `--follow`, not `--files-without-match` — they could never report a violation). Fixed three never-empty lints: Law 2 now `--type nix` (was firing on README prose), Law 4 regex anchored to assigned values (was matching its own "not 1000!" comment), Law 16 derivations lint excludes README.md. Law 1 whitelist generalized to any `osConfig ?` guard / `osConfig.<path> or <fallback>`. Law 10 burn-down corrected from "~21" to the actual 2 remaining files. No law semantics changed — this release makes the existing laws checkable.
- **v12.1 (2026-06-11)**: Roles architecture. profiles/ restructured into role folders (base, desktop, server, business, monitoring, gaming, appliance, mail) with sys/home lane halves; machine membership moved to a machines registry in flake.nix (channel + roles + pkgs per machine); HM bootstrap moved from profiles into flake glue; standalone homeConfigurations generated for every machine. Added Law 16 (Layer Purity: profiles & machines) with lints in §3.1 and a layer note in the domain map. Backup value-defaults absorbed into domains/data option defaults; hwc.home.{shell,development} renamed under hwc.home.core.* (Law 2).
- **v12.0 (2026-06-09)**: Full coherence pass from the 2026-06-09 audit. Fixed v11.2/v11.0 header/footer mismatch and duplicate "Section 5" numbering. Domain map rewritten to match disk (16 domains: added mail, notifications, server; removed phantom alerts). Law 2 self-contradiction fixed (`hwc.networking` is valid; the law is the mapping, not a list). Law 3 corrected to reference `paths.nix` (not `index.nix`). Law 4 de-fictionalized (`identity.nix` never existed; literals are the standard) and now documents the secrets generator. Law 7 extended to forbid orphaned `sys.nix`. Removed all references to the never-built `readme-butler`. Added Law 13 (Repo Hygiene), Law 14 (Flake Input Discipline), Law 15 (Runtime Hygiene). Added duplicate-systemd-service lint. Declared `nix flake check` as the target enforcement gate.
- **v11.2 (2026-05-20)**: documented dual HM activation paths; removed orphaned `profiles/home.nix`.
- **v11.1 (2026-03-12)**: post-v11.0 incremental updates; `options.nix` → `index.nix` migration (completed in intent; 16 stragglers remained until flagged 2026-06-09).
- **v11.0 (2026-03-07)**: options inlined into `index.nix`; mkContainer moved to `domains/lib/`; domain architecture restructured.
- **v10.x (2026-01/02)**: paths domain added, Law 2 strictness, Laws 9–12, infrastructure→system migration.
- **v9.x (2026-01-10)**: laws + mechanical validation focus.

**End of Charter v12.2**
