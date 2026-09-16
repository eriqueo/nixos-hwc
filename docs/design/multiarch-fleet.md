# Multi-architecture fleet — assumption audit and per-system output design

**Status:** design, not implemented. Nothing in this document has been applied.
**Date:** 2026-09-16
**Scope:** step 01 of the multiarch-fleet goal. Steps 02 and 03 are the mechanical
diffs this document decides; step 04 is unblocked by `## ARM development-server
prerequisites`.

Every verdict below that says `eval-fails`, `build-fails`, `silently-degrades` or
`benign` is either quoted from a command in `## Current-state evidence` or marked
`(read)` when it was determined by reading the file. No verdict here is a guess.

---

## Problem statement

`nixos-hwc` is single-architecture in two independent ways, and each has to be
fixed by a different layer. First, the flake's *output sets* are bound to one
system: `flake.nix:186` binds `system = "x86_64-linux"` as a plain `let` value and
`apps`, `packages` and `checks` are published as `apps.${system}` / `packages.${system}`
/ `checks.${system}` (`flake.nix:424`, `:436`, `:447`), so `nix eval .#checks` over
this flake returns exactly `["x86_64-linux"]` — an `aarch64-linux` consumer of this
flake has no lints, no `hwc-graph`, and no app. Second, the *shared development
environment* defaults to x86-only derivations: `profiles/base/home.nix:53-54` turns
`herdr` and `codex` on with `lib.mkDefault true` for every role that includes
`base`, which is every machine in the registry, and the herdr module's pinned
package refuses to evaluate on `aarch64-linux`. The machine registry itself is
**not** the problem — `flake.nix:351`/`:359` already thread a per-machine
`sysArch` into `nixpkgs.hostPlatform`, and `hwc-firestick` really does evaluate as
aarch64 today. The single-arch assumptions live above the registry (the output
sets) and below it (the packages), not in it.

---

## Inventory

25 rows. `owning layer` is the layer that must change to fix the row, not the layer
the text sits in.

| location (file:line) | assumption | failure mode on aarch64 | owning layer |
|---|---|---|---|
| `flake.nix:186` | `system = "x86_64-linux"` is a plain `let` binding, consumed by every output set and every non-firestick `pkgs` | `benign` in isolation — nothing reads it on an ARM machine — but it is the root that makes rows 2–4 single-system (evidence §3 cmd 1–3) | flake |
| `flake.nix:424` | `apps.${system}` — the app set exists for one system | `eval-fails` for a consumer: `nix eval .#apps.aarch64-linux.hwc-graph` has no such attribute (evidence §3 cmd 3 returns `["x86_64-linux"]`) | flake |
| `flake.nix:436` | `packages.${system}` — same for `hwc-graph` | `eval-fails` for a consumer (evidence §3 cmd 2 returns `["x86_64-linux"]`) | flake |
| `flake.nix:447` | `checks.${system}` — all 20 lints exist for one system | `benign` today (nothing asks for them on ARM) but it means an ARM machine gets **zero** charter enforcement. Evidence §3 cmd 1 returns `["x86_64-linux"]`; the 20 names are in §3 cmd 5 | flake |
| `flake.nix:405-420` | `hwc-graph-pkg = pkgs.writeScriptBin …` closes over the x86 `pkgs`, so the derivation is x86 even if the attribute were republished under another system name | `silently-degrades` — publishing `packages.aarch64-linux.hwc-graph = hwc-graph-pkg` would hand ARM consumers an x86 `python3` shebang (read) | flake |
| `flake.nix:216-219` | the `claude-cowork-linux` overlay reads `inputs.claude-cowork.packages.${prev.stdenv.hostPlatform.system}.default`; the upstream flake publishes **only** `x86_64-linux` | `eval-fails` when the attribute is demanded — proven, error quoted in §3 cmd 6. Lazy, so it does not break the firestick eval today | flake |
| `flake.nix:276` | `pkgs-firestick = mkPkgs "aarch64-linux" nixpkgs;` | `benign` — this is the proof `mkPkgs` is already arch-parameterised and needs no change | flake |
| `flake.nix:351`, `:359` | `sysArch = m.system or system;` → `{ nixpkgs.hostPlatform = sysArch; }` | `benign` — the registry's per-machine arch support already works end to end; evidence §3 cmd 4 evaluates `hwc-firestick` to `aarch64-linux` | flake |
| `flake.nix:315-321` | `firestick` sets `system = "aarch64-linux"` in the registry | `benign` — the working precedent (read) | flake |
| `profiles/base/home.nix:53` | `herdr.enable = lib.mkDefault true;` for every role carrying `base` | `eval-fails` on any ARM machine that does not opt out, via the herdr pin (evidence §3 cmd 7: `"herdr-pin": false`) | profile |
| `profiles/base/home.nix:54` | `codex.enable = lib.mkDefault true;` for every role carrying `base` | `benign` — the module default is `pkgs.codex` (`domains/home/apps/codex/index.nix:5`), which evaluates on aarch64 (evidence §3 cmd 7: `"pkgs.codex": true`). **Only the opt-in pin is x86.** | profile |
| `domains/home/apps/herdr/parts/package.nix:8` | `url = ".../herdr-linux-x86_64"` — an x86_64 release binary with no ARM asset in the URL scheme | `eval-fails`, guarded by the `meta.platforms` on the next row (read) | domain |
| `domains/home/apps/herdr/parts/package.nix:29` | `platforms = [ "x86_64-linux" ];` | `eval-fails` — nixpkgs refuses at `.drvPath`: *"Refusing to evaluate package 'herdr-0.8.2' … because it is not available on the requested hostPlatform"* (evidence §3 cmd 6). This is the **good** failure: loud, at eval | domain |
| `domains/home/apps/codex/parts/package.nix:19` | `url = ".../codex-x86_64-unknown-linux-musl.tar.gz"` | `silently-degrades` — `fetchurl` is a fixed-output derivation, so it fetches and unpacks identically on ARM. The pin has **no `meta.platforms`**, so its `.drvPath` evaluates clean on aarch64 (evidence §3 cmd 6: `codex-0.146.0.drv`) and would install an x86 binary that dies at `exec` | domain |
| `domains/home/apps/codex/parts/package.nix:26` | `mv "$out/bin/codex-x86_64-unknown-linux-musl" "$out/bin/codex"` | `silently-degrades` — same row's other half; the rename hides the arch in the installed name (read) | domain |
| `machines/laptop/home.nix:14` | the only site that selects the x86 codex pin (`hwc.home.apps.codex.package = …`) | `benign` — machine-scoped, on an x86 machine. Confirms the pin never reaches an ARM machine by default (read) | machine |
| `domains/home/apps/tuxedo/parts/package.nix:28` | x86_64 release tarball URL | `eval-fails`, guarded by the next row (read) | domain |
| `domains/home/apps/tuxedo/parts/package.nix:60` | `platforms = ["x86_64-linux"];` | `eval-fails` (evidence §3 cmd 7: `"tuxedo-pin": false`). Enabled by `profiles/desktop/home.nix:78`, **not** by `base` — an ARM headless server never reaches it | domain |
| `domains/home/apps/blender/parts/package.nix:159` | `platforms = [ "x86_64-linux" ];` on the upstream-binary Blender | `eval-fails` (evidence §3 cmd 8: `"blender-pin": false`). Enabled by `profiles/desktop/home.nix:60`, not `base` | domain |
| `domains/home/apps/t3code/index.nix:79` | `export VK_DRIVER_FILES=${pkgs.mesa}/share/vulkan/icd.d/intel_icd.x86_64.json` — hardcoded x86_64 Intel Vulkan ICD filename | `silently-degrades` — the surrounding `for device in /dev/dri/renderD*` loop only fires on an Intel vendor id (`0x8086`), which no ARM SBC reports, so the line is dead code on ARM rather than a crash; but if it ever did fire the path would not exist and Vulkan discovery would be pointed at nothing (read). `pkgs.mesa` itself evaluates on aarch64 (§3 cmd 7) | domain |
| `domains/home/apps/waybar/parts/packages.nix:36` | `++ lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [ linuxPackages.nvidia_x11.settings ]` | `benign` — **this is the existing arch-gate idiom and the one §6 must copy.** It is the only place in the repo that already does this correctly | domain |
| `domains/home/apps/hwc-dictation/index.nix:6` | `inputs.hwc-dictation.packages.${pkgs.stdenv.hostPlatform.system}` — same shape as the claude-cowork overlay | `benign` — the upstream flake publishes `["aarch64-darwin","aarch64-linux","x86_64-darwin","x86_64-linux"]` (evidence §3 cmd 6). Same shape, opposite verdict: the shape is not the defect, the upstream's system list is | domain |
| `machines/xps/home.nix:25` | `inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.electron_43` | `benign` — arch-correct interpolation on an x86 machine (read) | machine |
| `machines/{laptop,server,xps,kids}/hardware.nix` (`:88`, `:51`, `:72`, `:42`) | `nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";` | `benign` — `mkDefault`, and `flake.nix:359` sets the same value at normal priority from the registry. `machines/firestick/hardware.nix:35` is the aarch64 counterpart (read) | machine |
| `machines/firestick/home.nix:61-62`, `machines/kids/home.nix:31-32` | `herdr.enable = false; codex.enable = false;` — the current per-machine coping mechanism for an x86-only base default | `benign` but **misleading**: on firestick the herdr line encodes a platform fact as a machine preference; on kids (x86_64) the same two lines are a genuine leanness choice. §6 must not delete both pairs (read) | machine |
| `domains/monitoring/prometheus/parts/alerts.nix:14` | comment: *"Mechanically checked by `checks.x86_64-linux.alert-tier-exclusivity`"* | `benign` — documentation drift the moment checks become per-system; the check itself is arch-independent (see §5) (read) | domain |

---

## Current-state evidence

All commands run from the worktree on
`nightly/2026-09-16-nixos-multiarch-fleet-01-arch-assumption-audit-and-design`
(equal to `origin/main` for every `.nix` file). `nix` is not on this venue's
`PATH`; the absolute path `/run/current-system/sw/bin/nix` was used, and every
command was wrapped in `timeout 900`. No command timed out and no derivation was
realised. Full logs: `RUN_DIR/` (see the report).

### cmd 1 — `nix eval --json --apply builtins.attrNames .#checks`

```
["x86_64-linux"]
EXIT=0
```

### cmd 2 — `nix eval --json --apply builtins.attrNames .#packages`

```
["x86_64-linux"]
EXIT=0
```

### cmd 3 — `nix eval --json --apply builtins.attrNames .#apps`

```
["x86_64-linux"]
EXIT=0
```

### cmd 4 — `nix eval --raw .#nixosConfigurations.hwc-firestick.config.nixpkgs.hostPlatform.system`

It did **not** throw:

```
aarch64-linux
EXIT=0
```

This is the most load-bearing single result in the audit. The machine registry's
per-machine architecture works today; nothing in steps 02–04 needs to build it.

### cmd 5 — the 20 check names (`nix eval --json --apply builtins.attrNames .#checks.x86_64-linux`)

```
["aerc-bindings","aerc-rendering","alert-onfailure-units","alert-rules-parse",
 "alert-tier-exclusivity","charter-law1","charter-law10","charter-law12",
 "charter-law14","charter-law16","charter-law2","charter-law4","charter-law5",
 "charter-law7","mail-operator-rules","n8n-workflow-secret-literals",
 "nightly-review-silent","radicale-client-auth","sr-gauntlet-flock",
 "workbench-navigation"]
```

Count: `20`.

### cmd 6 — targeted aarch64 failure-mode probes

`claude-cowork-linux` demanded on the firestick (aarch64) package set —
`nix eval --raw .#nixosConfigurations.hwc-firestick.pkgs.claude-cowork-linux.name`:

```
error:
       … while evaluating the attribute 'claude-cowork.packages.aarch64-linux.default'
       error: attribute 'aarch64-linux' missing
       at /nix/store/gvwqvw0rwpspn90ad234jb4z0psljz4v-source/flake.nix:218:15:
          217|             claude-cowork-linux =
          218|               inputs.claude-cowork.packages.${prev.stdenv.hostPlatform.system}.default;
             |               ^
EXIT=1
```

Which systems the two interpolating inputs actually publish
(`builtins.attrNames (builtins.getFlake "<worktree>").inputs.<name>.packages`):

```
claude-cowork  : ["x86_64-linux"]
hwc-dictation  : ["aarch64-darwin","aarch64-linux","x86_64-darwin","x86_64-linux"]
```

`herdr` pin `.drvPath` on the aarch64 package set:

```
error: Refusing to evaluate package 'herdr-0.8.2' in
  domains/home/apps/herdr/parts/package.nix:26 because it is not available on the
  requested hostPlatform:
    hostPlatform.system = "aarch64-linux"
    package.meta.platforms = [
```

`codex` pin `.drvPath` on the same set — **no error**:

```
/nix/store/lyhc4bnanmydrdmbgx82szcqral7lx9w-codex-0.146.0.drv
```

### cmd 7 — batch `tryEval`-of-`.drvPath` on the aarch64 package set

`nix eval --impure --json --expr '… (builtins.tryEval (builtins.seq v.drvPath true)).success …'`

```json
{"codex-pin":true,"herdr-pin":false,"pi-pin":true,"pkgs.aider-chat":true,
 "pkgs.codex":true,"pkgs.gemini-cli":true,"pkgs.gnupg":true,"pkgs.mesa":true,
 "tuxedo-pin":false}
```

Read: of the seven apps `profiles/base/home.nix:50-58` enables by default, exactly
one — `herdr` — is unavailable on aarch64.

### cmd 8 — blender probe and the headless toolchain probe

```json
{"blender-pin":false}
{"electron":true,"fd":true,"nodejs":true,"pnpm":true,"promtool":true,
 "python3":true,"ripgrep":true}
```

### cmd 9 — fleet build-capability sweep

```
$ rg -n 'buildMachines|extra-platforms|extraPlatforms|binfmt|emulatedSystems|distributedBuilds' \
     domains profiles machines flake.nix --type nix
rg exit=1     # no matches
```

No cross-compilation, no emulation, no remote builder is declared anywhere in the
fleet. hwc-server can **evaluate** an aarch64 configuration (cmd 4 proves it) and
cannot **realise** a single aarch64 derivation.

### cmd 10 — CI and directory preconditions

```
$ git ls-files '.github/*'        # empty
$ git ls-files 'docs/design*'     # empty
```

The repo has no CI. The de-facto CI is `nix flake check` over `flake.nix:447-930`.

---

## Options

All three keep `homeConfigurations` and `nixosConfigurations` exactly as they are —
those are system-independent attribute sets keyed by machine name, and the registry
already carries the per-machine arch.

### Option A — hand-rolled `forAllSystems`

Add one `lib.genAttrs` helper in the existing `let` block and one package-set map,
then wrap the three output sets. No new flake input; `system` stays as the default
for the machine registry's `m.system or system` fallback, so the registry is
untouched.

```nix
    # in the let block, next to mkPkgs
    supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems    = lib.genAttrs supportedSystems;
    pkgsBySystem     = forAllSystems (s: mkPkgs s nixpkgs);

    # hwc-graph must close over the per-system pkgs, not the x86 `pkgs`
    mkHwcGraph = p: p.writeScriptBin "hwc-graph" ''…'';

  in {
    packages = forAllSystems (s: { hwc-graph = mkHwcGraph pkgsBySystem.${s}; });

    apps = forAllSystems (s: {
      hwc-graph = {
        type = "app";
        program = "${mkHwcGraph pkgsBySystem.${s}}/bin/hwc-graph";
        meta = { description = "NixOS HWC dependency graph CLI"; license = lib.licenses.mit; };
      };
    });

    checks = forAllSystems (s: mkChecks pkgsBySystem.${s} s);
  }
```

**Eval cost.** One extra full `mkPkgs` instantiation per added system on any
command that forces the whole output tree (`nix flake show`, `nix flake check`).
`pkgs-firestick` already pays this cost for aarch64 today, so the marginal cost for
the second system is *zero* if `pkgsBySystem."aarch64-linux"` is reused as
`pkgs-firestick` rather than instantiated twice. Per-attribute eval
(`nix eval .#checks.x86_64-linux.charter-law1`) is unchanged — `genAttrs` is lazy.

**Third architecture later.** One string in `supportedSystems`. That is the whole
diff, provided `mkChecks` is already arch-conditional.

### Option B — `flake-utils.eachDefaultSystem`

```nix
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = mkPkgs system nixpkgs; in {
        packages.hwc-graph = mkHwcGraph pkgs;
        apps.hwc-graph = { type = "app"; program = "${mkHwcGraph pkgs}/bin/hwc-graph"; };
        checks = mkChecks pkgs system;
      })
    // {
      # system-independent outputs have to be merged back in by hand
      nixosConfigurations = …;
      homeConfigurations  = …;
    };
```

`eachDefaultSystem` iterates `flake-utils.lib.defaultSystems`, which is
`[ "aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux" ]`. For this
fleet that **over-publishes by 2 of 4**: the two darwin systems are advertised and
will fail at eval the moment anyone touches them, because `mkPkgs` sets
`nvidia.acceptLicense`, the overlays backport Linux-only packages, and the
machine-bound checks reference Linux NixOS configs. Narrowing it back requires
`eachSystem [ … ]`, at which point the input buys nothing that `lib.genAttrs`
does not already provide.

**Eval cost.** Same per-system cost as A, plus the `//` merge restructures the
entire `outputs` body — a large diff across a 940-line file whose `let` block feeds
both halves. **Third architecture later.** Free if it is in `defaultSystems`, and
the same one-string edit as A if it is not. **New inputs:** one, plus a
`flake.lock` change — which this goal's cards 02–03 explicitly forbid.

### Option C — asymmetric publication

Publish `apps` and `packages` on `x86_64-linux` only, and split `checks` so that
aarch64 gets the source-lint subset and nothing else.

```nix
    sourceLints = p: {
      charter-law1  = mkCharterLint p "law1-osconfig-safety" [ … ];
      # … the other 8 charter-law lints, alert-tier-exclusivity,
      #   n8n-workflow-secret-literals, nightly-review-silent
    };
    machineChecks = p: { radicale-client-auth = …; workbench-navigation = …; /* … */ };

  in {
    apps.${system}     = { hwc-graph = …; };   # unchanged, x86_64 only
    packages.${system} = { hwc-graph = …; };   # unchanged, x86_64 only

    checks = {
      x86_64-linux  = sourceLints pkgs // machineChecks pkgs;
      aarch64-linux = sourceLints pkgs-firestick;
    };
  }
```

**Eval cost.** Lowest of the three: no new package-set instantiation at all
(`pkgs-firestick` already exists), and the aarch64 check set is 12 attributes, not
20. **Third architecture later.** A third hand-written `checks.<sys>` entry plus a
third package set — the cost grows linearly and by hand, which is the weakness.
**Over-publishing risk:** zero, but it *under*-publishes: `nix build .#hwc-graph`
on an ARM machine still fails.

### Comparison matrix

| | eval cost | third-arch cost | over-publishing risk | new inputs | blast radius of the change |
|---|---|---|---|---|---|
| **A — `forAllSystems`** | +1 `mkPkgs` per system, zero if `pkgs-firestick` is reused; lazy per-attribute | one string in `supportedSystems` | none — the list is explicit | none | `flake.nix` only: the `let` block + the three output attrs (~40 lines) |
| **B — `flake-utils`** | same as A, plus a whole-`outputs` restructure | free inside `defaultSystems`, one string outside | **high** — 2 of 4 `defaultSystems` are darwin and cannot evaluate here | 1 (`flake-utils`) + `flake.lock` churn | `flake.nix` `outputs` body rewritten end to end (~500 lines re-indented) |
| **C — asymmetric** | lowest — reuses `pkgs-firestick`, 12 aarch64 attrs | linear, hand-written per arch | none, but under-publishes `apps`/`packages` | none | `flake.nix` only: the `checks` attr split (~25 lines) |

---

## Check portability

Verified against `flake.nix:447-930` rather than against the card's list. The
mechanical discriminator is whether the check's `let` block reads
`self.homeConfigurations` or `self.nixosConfigurations`:

```
$ rg -n 'self\.(homeConfigurations|nixosConfigurations)' flake.nix
468:        home = self.homeConfigurations."eric@hwc-laptop".config;
511:        home = self.homeConfigurations."eric@hwc-laptop".config;
560:        home = self.homeConfigurations."eric@hwc-server".config;
595:        home = self.homeConfigurations."eric@hwc-server".config;
648:        home = self.homeConfigurations."eric@hwc-server".config;
773:        ruleFiles = self.nixosConfigurations."hwc-server".config.…;
790:        server = self.nixosConfigurations."hwc-server".config;
818:        server = self.nixosConfigurations."hwc-server".config;
```

Eight machine-bound, twelve source-lint. **Two corrections to the working list this
card started from:**

1. There are **nine** `charter-law*` lints, not eight: `law1 law2 law4 law5 law7
   law10 law12 law14 law16` (`flake.nix:870-929`).
2. **`alert-tier-exclusivity` (`flake.nix:707`) is source-lint, not machine-bound.**
   It does `import ./domains/monitoring/prometheus/parts/alerts.nix { inherit lib; }`
   at `flake.nix:708` and never touches a machine config. It is a pure evaluation
   over a `parts/` file, and is arch-independent. Its sibling
   `alert-rules-parse` (`flake.nix:772`) *is* machine-bound — that is the pair's
   whole point, and it is easy to mis-sort them.

### source-lint (12) — arch-independent by construction

| check | line | why portable |
|---|---|---|
| `charter-law1` | 870 | `rg` over `${self}` |
| `charter-law2` | 873 | `rg` over `${self}` |
| `charter-law4` | 876 | `rg` over `${self}` |
| `charter-law5` | 879 | `rg`+`xargs` over `${self}` |
| `charter-law7` | 882 | `rg` over `${self}` |
| `charter-law10` | 885 | `fd` + `rg` over `${self}` |
| `charter-law12` | 900 | shell loop + `rg` over `${self}` |
| `charter-law14` | 905 | `rg` over `flake.nix` |
| `charter-law16` | 924 | `rg` over `profiles/` |
| `alert-tier-exclusivity` | 707 | pure `builtins.match` over an imported `parts/` file |
| `n8n-workflow-secret-literals` | 916 | `python3` over `${self}` |
| `nightly-review-silent` | 851 | `rg` over one `index.nix` |

The *result* of each of these is arch-independent, but the **derivation is not
arch-free**: each is a `pkgs.runCommand` with `pkgs.ripgrep` / `pkgs.fd` /
`pkgs.python3` in `nativeBuildInputs`. Publishing them under
`checks.aarch64-linux` therefore requires an aarch64 builder to *realise* them —
which the fleet does not have (evidence §3 cmd 9). `ripgrep`, `fd` and `python3`
all evaluate on aarch64 (§3 cmd 8), so the attributes are honest; they are simply
unbuildable here today. **This is the single most important consequence in this
document: publishing aarch64 checks before §7 is answered creates attributes that
`nix flake check` on an ARM host would try to build and could not.**

### machine-bound (8) — and what duplication would mean

| check | line | machine it evaluates | duplicating under `checks.aarch64-linux` would be |
|---|---|---|---|
| `radicale-client-auth` | 467 | `eric@hwc-laptop` (x86) | **actively misleading** — it would run an x86 machine's credential wiring in an attribute named aarch64. The subject does not change with the check's system; only the builder does |
| `workbench-navigation` | 510 | `eric@hwc-laptop` (x86) | **actively misleading** — same reason. It also `assert`s at eval, so the assertion fires identically under either system name, giving a false impression of ARM coverage |
| `aerc-bindings` | 559 | `eric@hwc-server` (x86) | **actively misleading** |
| `aerc-rendering` | 594 | `eric@hwc-server` (x86) | **actively misleading**, and worse than the others: its `runCommand` actually *executes* the generated aerc filter, so it needs a real aarch64 builder to produce an x86 machine's answer |
| `mail-operator-rules` | 647 | `eric@hwc-server` (x86) | **actively misleading**; also executes `python3` tests |
| `alert-rules-parse` | 772 | `hwc-server` (x86) | **meaningless** — `promtool check rules` over an x86 machine's rule files; `promtool` itself evaluates on aarch64 (§3 cmd 8) but the rule files are the same bytes, so the second run proves nothing new |
| `alert-onfailure-units` | 789 | `hwc-server` (x86) | **meaningless** — pure eval over one machine's unit set; the `runCommand` is a `touch $out` |
| `sr-gauntlet-flock` | 817 | `hwc-server` (x86) | **meaningless** — resolves `flock` on the *evaluated x86 unit's* `PATH`; running the resolution on an ARM builder tests the ARM builder, not the server |

None of the eight becomes meaningful under an aarch64 key until there is an
aarch64 *machine in the registry whose config they read*. The correct future move
is not to duplicate them by system but to parameterise them by **machine** — i.e.
`aerc-bindings` should one day take the machine name, not the build system. That is
out of scope for cards 02–03 and is noted here so nobody reads the asymmetry as an
oversight.

---

## Arch-gating the shared dev environment

### Where the gate lives

**In `profiles/base/home.nix`, as a `mkDefault` assignment — not in the app
modules' `config`, and not in a new shared helper.**

The reasoning is a three-way constraint:

- **It cannot live in the app module's `config` as a silent `mkIf`.** Writing
  `config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.system == "x86_64-linux") { … }`
  makes `herdr.enable = true` a silent no-op on ARM. A machine that explicitly asks
  for herdr and gets nothing, with no error, is strictly worse than today's loud
  `Refusing to evaluate package 'herdr-0.8.2'`. The current failure is a *good*
  failure and the gate must not destroy it.
- **Charter Law 16 permits the assignment and forbids the alternatives.**
  Law 16 says profile halves "contain ONLY option assignments (`mkDefault` for
  anything a machine may override) and domain imports" and forbids
  `mkDerivation`, `fetchurl`, `writeShellScript*`, inline `systemd.services`
  bodies, option *declarations*, and machine names. A conditional *value* in an
  `mkDefault` assignment is still an option assignment. The wired law16 lint
  (`flake.nix:924-929`) greps `profiles/` for `mkDerivation|fetchurl|writeShellScript`,
  machine names, role-to-role imports, and `mkOption|mkEnableOption` — the proposed
  line trips none of them. A **new shared helper** under `profiles/` *would* risk
  Law 16 (it is neither an assignment nor a domain import), and a helper under
  `domains/lib/` would be a new file that Law 10 and `CLAUDE.md`'s
  "Before adding a file" rule both make expensive to justify for one boolean.
- **`pkgs` is already in scope.** `profiles/base/home.nix:9` is
  `{ config, lib, pkgs, nixosApiVersion ? "unstable", ... }:`.

### The code sketch — matching `waybar/parts/packages.nix:36` exactly

The existing idiom is the literal system comparison, not `.isx86_64`:

```nix
# domains/home/apps/waybar/parts/packages.nix:36  — the precedent
] ++ lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
  linuxPackages.nvidia_x11.settings
]
```

So the gate reads:

```nix
# profiles/base/home.nix — replacing line 53
    apps = {
      gpg.enable = lib.mkDefault true;
      yazi.enable = lib.mkDefault true;

      # herdr ships one x86_64 release binary and declares
      # meta.platforms = [ "x86_64-linux" ], so demanding it on aarch64 is an
      # eval error, not a build error. Default it off there; a machine that
      # really wants it can still set enable = true and get the honest error.
      # Idiom matches domains/home/apps/waybar/parts/packages.nix:36.
      herdr.enable = lib.mkDefault (pkgs.stdenv.hostPlatform.system == "x86_64-linux");

      codex.enable = lib.mkDefault true;   # unchanged — see below
      pi.enable = lib.mkDefault true;
      aider.enable = lib.mkDefault true;
      gemini-cli.enable = lib.mkDefault true;
    };
```

### Only herdr needs a gate

This is the finding that shrinks card 03. Of the seven apps `base` enables,
evidence §3 cmd 7 proves six evaluate clean on aarch64:

```json
{"pkgs.codex":true,"pkgs.gemini-cli":true,"pkgs.aider-chat":true,
 "pkgs.gnupg":true,"pi-pin":true,"herdr-pin":false}
```

`codex`'s module default is `pkgs.codex` (`domains/home/apps/codex/index.nix:5`:
`codexPkg = if cfg.package != null then cfg.package else (pkgs.codex or null)`), and
the x86 pin is selected only by `machines/laptop/home.nix:14`. `pi`'s pin is a
`buildNpmPackage` from a GitHub tarball, which is arch-portable by construction.
`yazi` is stock nixpkgs. **Do not gate `codex` in `base`.** Gating it would be a
change that fixes nothing and removes a working ARM tool.

### What happens to the existing opt-out lines

They are **not** symmetric and card 03 must not treat them as one edit:

- `machines/firestick/home.nix:61` (`herdr.enable = false;`) becomes redundant —
  the gate already defaults it off on aarch64. **Remove it**, because leaving it
  encodes a platform fact as a machine preference and hides why the stick has no
  herdr. `machines/firestick/home.nix:62` (`codex.enable = false;`) is **not**
  redundant and must stay: codex works on ARM, and the stick's opt-out is a
  leanness decision (the file's own header says so).
- `machines/kids/home.nix:31-32` — kids is `x86_64-linux`
  (`machines/kids/hardware.nix:42`). Both lines stay, verbatim. Deleting them
  because they look like the firestick pair would silently install herdr, codex,
  aider and gemini-cli on the kids' retro-gaming machine.

### What an ARM machine gets instead

**Instead of herdr: nothing.** There is no drop-in replacement in this repo, and
inventing one is out of scope. The honest statement for an ARM development server
is that the agent multiplexer is unavailable until upstream publishes an ARM
asset — see §7, which lists confirming that as a prerequisite rather than assuming
it. The rest of the agent toolchain (`codex`, `pi`, `aider`, `gemini-cli`) is
available on ARM today and needs no substitute.

---

## ARM development-server prerequisites

This section is the spec for card 04. It states what a human must decide and what
must be confirmed before `aarch64-linux` can be called a supported
development-server target.

### 1. Build capability — the decision being asked for

The fleet has **none** today. Evidence §3 cmd 9: the sweep for
`buildMachines|extra-platforms|extraPlatforms|binfmt|emulatedSystems|distributedBuilds`
across `domains/ profiles/ machines/ flake.nix` returns no matches. hwc-server can
evaluate `hwc-firestick` as aarch64 (§3 cmd 4) and cannot realise one aarch64
derivation. There are two ways to change that, and they are not interchangeable:

| | **Native ARM builder** (`nix.buildMachines` + remote store) | **binfmt emulation** (`boot.binfmt.emulatedSystems = [ "aarch64-linux" ]` on hwc-server) |
|---|---|---|
| What it needs | A real aarch64 machine, powered, on the tailnet, with an SSH key in hwc-server's `nix.buildMachines` and the host key trusted; plus `nix.distributedBuilds = true` | One boolean and a rebuild of hwc-server. `qemu-user` is registered as a binfmt handler |
| Speed | Native. A `buildNpmPackage` like `pi` costs what it costs | 3–10× slower for compute-bound builds; `buildNpmPackage`/`electron` rebuilds are the painful case |
| Fidelity | Exact. This is the only option that can prove an ARM binary *runs* | Good for producing store paths, weak for proving runtime behavior — qemu-user's syscall and threading emulation is not the target kernel |
| Failure mode when absent | Builds queue and fail with "a 'aarch64-linux' with features {} is required" | Nothing; it is a local capability |
| Ongoing cost | A second physical machine to keep alive and updated | A slower hwc-server rebuild surface; nothing to maintain |
| Right for | Card 04 if the goal is *a real ARM development server* | Card 04 if the goal is *proving the aarch64 outputs realise at all* |

**The recommendation to the human:** do binfmt first, because it is one line and it
converts §5's "the aarch64 source-lints are unbuildable here" from a blocker into a
measurable fact; add a native builder only when an actual ARM machine exists and
runtime fidelity starts to matter. Both are `boot.*`/`nix.*` system options and are
**out of scope for cards 01–03**; card 04 owns the choice.

### 2. Toolchain pieces with no ARM source path today

Confirmed individually, not assumed:

| piece | ARM source path today | confirmed by |
|---|---|---|
| `herdr` | **None.** The pin fetches one `herdr-linux-x86_64` asset (`parts/package.nix:8`) and declares `platforms = [ "x86_64-linux" ]` (`:29`). `.drvPath` refuses to evaluate on aarch64 | §3 cmd 6 + cmd 7 (`"herdr-pin": false`) |
| `codex` | **Yes** — `pkgs.codex` from nixpkgs evaluates on aarch64. The repo's x86 pin (`parts/package.nix:19`) is opt-in and selected only by `machines/laptop/home.nix:14` | §3 cmd 7 (`"pkgs.codex": true`) |
| `pi` | **Yes** — `parts/package.nix` is a `buildNpmPackage` from `fetchFromGitHub`, built from source | §3 cmd 7 (`"pi-pin": true`) |
| `t3code` | **Partial.** The module packages no source (`index.nix:12-13`): T3 Code is a pnpm monorepo built from Eric's working tree at `~/600_apps/t3code`, and Nix supplies only Electron + node. `pkgs.electron`, `pkgs.nodejs` and `pkgs.pnpm` all evaluate on aarch64, so the *Nix* half is portable. What is **unknown** is whether the fork's own `pnpm build` produces a working ARM bundle and whether any of its transitive native npm modules ships an ARM prebuild. Also: `index.nix:79`'s `intel_icd.x86_64.json` is dead on ARM (no `0x8086` vendor id) but is still a hardcoded x86 path | §3 cmd 8 + read of `index.nix:12-21,48-79` |
| `tuxedo`, `blender` | **None**, and they do not matter: both are enabled by `profiles/desktop/home.nix` (`:78`, `:60`), not `base`. A headless ARM development server carries `base` + a server-ish role and never reaches them | §3 cmd 7/8 + read of `profiles/desktop/home.nix` |
| `claude-cowork-linux` | **None.** Upstream publishes `["x86_64-linux"]` only. Lazy, so it does not break an ARM eval until demanded — but any ARM machine whose role enables the claude-desktop app module hits `error: attribute 'aarch64-linux' missing` | §3 cmd 6 |

**What card 04 must confirm that this audit could not:** whether upstream herdr has
since published an ARM asset (this audit read only the pinned v0.8.2 URL scheme in
the repo; it did not query the upstream release list), and whether the t3code fork
builds on ARM. Neither is answerable from the repo.

### 3. The DataX boundary

`ContractorCTO/datax` and `ContractorCTO/dx-mcp` are **upstream** repositories and
are out of scope for all fleet work. Nothing in `nixos-hwc` builds or deploys them.

What *is* in this repo is `domains/business/datax-monitor` — a single `index.nix`
that runs a **native, out-of-store Node app** from `~/600_apps/datax-monitor`
(`index.nix:7`, and `index.nix:106` defaults `projectDir` to
`${config.hwc.paths.user.home}/600_apps/datax-monitor`, used as
`WorkingDirectory` by three units at `:218`, `:241`, `:263`). Because the app is
run in place rather than packaged, there is no derivation to cross-build: an "ARM
proof of datax-monitor" means **`pkgs.nodejs` on aarch64 plus an `npm install` of
that working tree succeeding on ARM hardware** — a runtime question about the app's
own native dependencies, not a Nix packaging question. `pkgs.nodejs` evaluates on
aarch64 (§3 cmd 8); the rest is card 04's to test on real hardware. Card 04 must not
read this as license to touch anything under `ContractorCTO/*`.

---

## Recommendation

**Adopt Option A, with Option C's asymmetric `checks` split inside it** — i.e.
`forAllSystems` for the mechanism, asymmetric content for `checks`. Named
combination: **A + C**.

From the matrix: Option B is disqualified on three columns at once — it is the only
option that needs a new input and a `flake.lock` change (which this goal forbids),
it over-publishes two darwin systems that cannot evaluate against `mkPkgs`'s
Linux-only overlays, and its blast radius is a rewrite of the whole `outputs` body
rather than a local edit. Between A and C, A wins on third-arch cost (one string
versus a hand-written block per architecture) and C wins on eval cost and on being
honest about what an aarch64 check set can contain. They are not mutually
exclusive: use `forAllSystems` to *generate* the sets and make the `checks`
generator arch-conditional, so `checks.aarch64-linux` carries the 12 source-lints
and `checks.x86_64-linux` carries all 20. Reuse `pkgs-firestick` as
`pkgsBySystem."aarch64-linux"` so the added eval cost is zero.

`apps` and `packages` should be published for both systems under A — `hwc-graph` is
a `writeScriptBin` around `python3`, which evaluates on aarch64 — but `hwc-graph-pkg`
must first be turned into a function of `pkgs` (inventory row `flake.nix:405-420`),
or the ARM attribute silently hands out an x86 interpreter.

### Card 02 — per-system flake outputs

**May touch:** `flake.nix` only. (No `flake.lock`, no new input, no
`domains/`/`profiles/`/`machines/`.)

**Done-condition:** `nix eval --json --apply builtins.attrNames .#checks` returns
`["aarch64-linux","x86_64-linux"]`, `nix eval --json --apply builtins.attrNames
.#checks.x86_64-linux` still returns all 20 names listed in §3 cmd 5, and
`.#checks.aarch64-linux` returns exactly the 12 source-lint names from §5 — with
`nix flake check --no-build` still clean on the branch.

### Card 03 — arch-gate the shared dev environment

**May touch:** `profiles/base/home.nix`, `machines/firestick/home.nix`,
`profiles/README.md` and `machines/README.md` (Law 12). Explicitly **not**
`machines/kids/home.nix` — kids is x86_64 and its opt-out lines are load-bearing.
Explicitly **not** `domains/home/apps/codex/**` — codex needs no gate (§6).

**Done-condition:** with `machines/firestick/home.nix:61`'s `herdr.enable = false;`
deleted, `nix eval --raw .#homeConfigurations."eric@hwc-firestick".activationPackage.drvPath`
still returns a store path (it does today —
`/nix/store/87cmbwswkvwgqkllgp1wkdf3f6k67nkk-home-manager-generation.drv`), and
`nix eval --raw .#homeConfigurations."eric@hwc-laptop".activationPackage.drvPath`
is byte-identical before and after the change.

### Out of scope for all of 01–03

- No `flake.lock` change, and no new flake input (Option B is rejected, so this is
  unconditional).
- No `nixos-rebuild`, no `hms`, no `home-manager switch`, no `systemctl`, no
  realised derivation. `nix eval` and `nix flake check --no-build` only.
- No change to the machine registry's role assignments, channels, or `pkgs`
  selections (`flake.nix:288-322`).
- No new machine, and no `boot.binfmt.emulatedSystems` / `nix.buildMachines` /
  `nix.distributedBuilds`. Build capability is card 04's decision (§7.1).
- No change to `domains/home/apps/{tuxedo,blender,t3code}/**` — desktop-role or
  working-tree apps that a headless ARM target never reaches (§7.2).
- No repackaging of `herdr` from source and no change to the `claude-cowork`
  overlay. Both are upstream-availability problems (§7.2), not flake-shape
  problems.
- No change to `docs/README.md`. Per the run-wrapper's shared-index rule this
  design deliberately does not edit it; **if `docs/design/` should be listed in
  `docs/README.md`, that is a one-line edit for a human or a later card to make at
  the documented anchor.**
