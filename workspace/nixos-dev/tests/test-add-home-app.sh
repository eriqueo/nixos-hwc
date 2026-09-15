#!/usr/bin/env bash
# workspace/nixos-dev/tests/test-add-home-app.sh
#
# Regression test for workspace/nixos-dev/add-home-app.sh.
#
# Drives the REAL script (no re-implementation of its logic) against isolated
# git + Nix fixtures:
#
#   <workdir>/nixpkgs/        a path-input flake standing in for nixpkgs
#   <workdir>/home-manager/   a path-input flake standing in for home-manager
#   <workdir>/repo/           a fixture nixos-hwc checkout on a feature branch
#   <workdir>/repo-main/      the same checkout, left on `main`
#
# The fixture repo's flake THROWS on every output except the attribute NAMES of
# nixosConfigurations. That is deliberate: it makes "does not evaluate unrelated
# outputs" a mechanically detectable property rather than a claim. `nix flake
# show` (what the script used before) blows up on this fixture; the targeted
# `nix eval ... --apply builtins.attrNames` does not.
#
# Usage:
#   workspace/nixos-dev/tests/test-add-home-app.sh
#   HWC_TEST_WORKDIR=/some/scratch workspace/nixos-dev/tests/test-add-home-app.sh
#
# Exit 0 = all cases passed. Exit 1 = at least one case failed.

set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/../add-home-app.sh"

if [[ ! -x "$SUT" ]]; then
  echo "FATAL: system under test not executable: $SUT" >&2
  exit 1
fi

# Nix is not always on a bare PATH (agent sandboxes, cron); the repo's own
# system profile always has it.
export PATH="/run/current-system/sw/bin:$PATH"
if ! command -v nix >/dev/null 2>&1; then
  echo "FATAL: nix not found on PATH" >&2
  exit 1
fi

WORKDIR="${HWC_TEST_WORKDIR:-}"
if [[ -z "$WORKDIR" ]]; then
  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR"' EXIT
else
  # .nixos-worktrees too: the main-refusal case creates one there, and a
  # survivor makes the next run refuse ("worktree path already exists").
  rm -rf "${WORKDIR:?}/nixpkgs" "${WORKDIR:?}/home-manager" \
         "${WORKDIR:?}/repo" "${WORKDIR:?}/repo-main" \
         "${WORKDIR:?}/.nixos-worktrees"
  mkdir -p "$WORKDIR"
fi

PASS=0
FAIL=0
FAILED_CASES=()

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); FAILED_CASES+=("$1"); printf '  FAIL %s\n' "$1"; }

assert_eq() { # name expected actual
  if [[ "$2" == "$3" ]]; then ok "$1"; else
    bad "$1"; printf '       expected: %s\n       actual:   %s\n' "$2" "$3"; fi
}
assert_contains() { # name haystack needle
  if [[ "$2" == *"$3"* ]]; then ok "$1"; else
    bad "$1"; printf '       missing substring: %s\n' "$3"; fi
}
assert_not_contains() { # name haystack needle
  if [[ "$2" != *"$3"* ]]; then ok "$1"; else
    bad "$1"; printf '       unexpected substring: %s\n' "$3"; fi
}
assert_file() { # name path
  if [[ -f "$2" ]]; then ok "$1"; else bad "$1"; printf '       no such file: %s\n' "$2"; fi
}
assert_no_file() { # name path
  if [[ ! -e "$2" ]]; then ok "$1"; else bad "$1"; printf '       should not exist: %s\n' "$2"; fi
}

#==============================================================================
# FIXTURES
#==============================================================================

build_fixture_nixpkgs() {
  mkdir -p "$WORKDIR/nixpkgs"
  cat > "$WORKDIR/nixpkgs/flake.nix" <<'EOF'
{
  description = "fixture nixpkgs";
  outputs = { self }: let
    drv = pname: version: description: derivation {
      inherit pname version;
      name = "${pname}-${version}";
      builder = "/bin/sh";
      system = "x86_64-linux";
      meta = { inherit description; };
    };
  in {
    legacyPackages.x86_64-linux = {
      fixtureapp = drv "fixtureapp" "1.0" "Fixture one-package application";
      hmnative   = drv "hmnative" "2.0" "Fixture app with native Home Manager support";
      hmnativedir = drv "hmnativedir" "2.1" "Fixture app whose HM module is a directory";
      dupapp     = drv "dupapp" "3.0" "Fixture app exposed under two output sets";
    };
    # dupapp is reachable as BOTH packages.* and legacyPackages.* — this is what
    # makes "multiple exact top-level matches" a reachable branch, not dead code.
    packages.x86_64-linux = {
      dupapp = drv "dupapp" "3.0" "Fixture app exposed under two output sets";
    };
  };
}
EOF
}

build_fixture_home_manager() {
  mkdir -p "$WORKDIR/home-manager/modules/programs"
  cat > "$WORKDIR/home-manager/flake.nix" <<'EOF'
{
  description = "fixture home-manager";
  outputs = { self }: { };
}
EOF
  # Presence of modules/programs/<name>.nix IS how Home Manager declares
  # programs.<name>. hmnative has one; fixtureapp deliberately does not.
  cat > "$WORKDIR/home-manager/modules/programs/hmnative.nix" <<'EOF'
{ ... }: { options.programs.hmnative = {}; }
EOF
  # Home Manager uses BOTH layouts. firefox and vesktop are directories, kitty
  # is a flat file; a detector that only knows one form calls half the native
  # modules "simple".
  mkdir -p "$WORKDIR/home-manager/modules/programs/hmnativedir"
  cat > "$WORKDIR/home-manager/modules/programs/hmnativedir/default.nix" <<'EOF'
{ ... }: { options.programs.hmnativedir = {}; }
EOF
}

build_fixture_repo() { # dest branch
  local dest="$1" branch="$2"
  mkdir -p "$dest/domains/lib" "$dest/domains/home/apps/existingapp" "$dest/machines/fixturehost"

  cat > "$dest/flake.nix" <<EOF
{
  description = "fixture nixos-hwc";
  inputs = {
    nixpkgs.url      = "path:$WORKDIR/nixpkgs";
    home-manager.url = "path:$WORKDIR/home-manager";
  };
  outputs = { self, nixpkgs, home-manager }: {
    # Values THROW on purpose: attribute NAMES must be resolvable without
    # evaluating any machine. Anything that walks the outputs (nix flake show)
    # fails here, which is the regression this fixture pins.
    nixosConfigurations = {
      "hwc-fixturehost" = throw "fixture: nixosConfigurations values must not be evaluated";
      "hwc-other"       = throw "fixture: nixosConfigurations values must not be evaluated";
    };
    packages.x86_64-linux.boom = throw "fixture: unrelated outputs must not be evaluated";
    checks.x86_64-linux.boom   = throw "fixture: unrelated outputs must not be evaluated";
  };
}
EOF

  cp "$SCRIPT_DIR/../../../domains/lib/mkSimpleApp.nix" "$dest/domains/lib/mkSimpleApp.nix"

  cat > "$dest/domains/home/apps/README.md" <<'EOF'
# Home Apps

## Purpose
User application configuration via Home Manager.

## Boundaries
- Manages: App configs, dotfiles, user packages, desktop entries
- Does NOT manage: System deps

## Structure
```
apps/
├── existingapp/    # An app that was already here
└── ... (30+ apps)
```

## Changelog
- 2026-01-01: Fixture baseline.
EOF

  cat > "$dest/domains/home/apps/existingapp/index.nix" <<'EOF'
# domains/home/apps/existingapp/index.nix
import ../../../lib/mkSimpleApp.nix {
  name = "existingapp";
  description = "existing fixture app";
  package = pkgs: pkgs.hello;
}
EOF
  cat > "$dest/domains/home/apps/existingapp/README.md" <<'EOF'
# existingapp

## Purpose
Fixture sibling so the apps directory is populated.

## Boundaries
- ✅ Manages: nothing real.

## Structure
- `index.nix` — mkSimpleApp call.

## Changelog
- 2026-01-01: Fixture baseline.
EOF

  cat > "$dest/machines/fixturehost/home.nix" <<'EOF'
# machines/fixturehost/home.nix
{ config, lib, pkgs, ... }:
{
  # Apps enabled on this machine specifically
  hwc.home.apps = {
    existingapp.enable = true;
  };
}
EOF

  git -C "$dest" init -q -b main
  git -C "$dest" config user.email "fixture@example.com"
  git -C "$dest" config user.name "Fixture"
  git -C "$dest" add -A
  git -C "$dest" commit -q -m "fixture baseline"
  if [[ "$branch" != "main" ]]; then
    git -C "$dest" checkout -q -b "$branch"
  fi
  # Generate the real flake.lock so the script reads a lock Nix itself wrote.
  ( cd "$dest" && nix --extra-experimental-features 'nix-command flakes' \
      flake lock >/dev/null 2>&1 )
  git -C "$dest" add -A >/dev/null 2>&1
  git -C "$dest" commit -q -m "fixture lock" >/dev/null 2>&1 || true
}

manifest() { # dir -> sorted list of tracked+untracked paths and their hashes
  ( cd "$1" && find . -path ./.git -prune -o -type f -print | sort | \
      while IFS= read -r f; do printf '%s %s\n' "$(cksum <"$f" | cut -d' ' -f1)" "$f"; done )
}

#==============================================================================
# CASES
#==============================================================================

echo "workdir: $WORKDIR"
echo "building fixtures..."
build_fixture_nixpkgs
build_fixture_home_manager
build_fixture_repo "$WORKDIR/repo" "feat/fixture"
build_fixture_repo "$WORKDIR/repo-main" "main"

REPO="$WORKDIR/repo"
PROMPTS=("Enter package name" "Select [" "Proceed with adding" "Continue anyway" "Apply configuration now" "Run full build test")

# Sets the globals OUT and RC. Deliberately NOT a command substitution: RC has
# to survive into the caller's shell, and a $(...) subshell would swallow it.
OUT=""
RC=0
run_sut() {
  ( cd "$REPO" && timeout 300 "$SUT" "$@" </dev/null ) >"$WORKDIR/last-run.txt" 2>&1
  RC=$?
  OUT="$(cat "$WORKDIR/last-run.txt")"
}

echo
echo "CASE 1 — --dry-run --no-interactive writes nothing and never reads stdin"
BEFORE="$(manifest "$REPO")"
run_sut --dry-run --no-interactive --machine hwc-fixturehost fixtureapp; RC1=$RC
AFTER="$(manifest "$REPO")"
assert_eq "dry run exits 0" "0" "$RC1"
assert_eq "dry run leaves the tree byte-identical" "$BEFORE" "$AFTER"
assert_eq "dry run leaves git clean" "" "$(git -C "$REPO" status --porcelain)"
for p in "${PROMPTS[@]}"; do assert_not_contains "dry run emits no prompt: $p" "$OUT" "$p"; done
assert_contains "dry run names the target machine" "$OUT" "hwc-fixturehost"
assert_contains "dry run identifies native HM support absence" "$OUT" "simple"
assert_not_contains "dry run does not touch unrelated flake outputs" "$OUT" "must not be evaluated"

echo
echo "CASE 2 — --dry-run --no-interactive identifies native Home Manager support"
run_sut --dry-run --no-interactive --machine hwc-fixturehost hmnative; RC2=$RC
assert_eq "native dry run exits 0" "0" "$RC2"
assert_contains "native dry run reports native support" "$OUT" "native"
assert_contains "native dry run names programs.hmnative" "$OUT" "programs.hmnative"

echo
echo "CASE 2b — native detection also sees the directory module layout"
run_sut --dry-run --no-interactive --machine hwc-fixturehost hmnativedir; RC2B=$RC
assert_eq "directory-module dry run exits 0" "0" "$RC2B"
assert_contains "directory-module app is detected as native" "$OUT" "App type: native"
assert_contains "directory-module app names its HM option" "$OUT" "programs.hmnativedir"

echo
echo "CASE 3 — zero exact matches fails loudly with a stable code"
run_sut --dry-run --no-interactive --machine hwc-fixturehost nosuchappatall; RC3=$RC
assert_eq "no-match exit code is 3" "3" "$RC3"
assert_contains "no-match explains itself" "$OUT" "no exact top-level match"

echo
echo "CASE 4 — multiple exact matches fails loudly with candidates"
run_sut --dry-run --no-interactive --machine hwc-fixturehost dupapp; RC4=$RC
assert_eq "ambiguous exit code is 4" "4" "$RC4"
assert_contains "ambiguous names candidate 1" "$OUT" "legacyPackages.x86_64-linux.dupapp"
assert_contains "ambiguous names candidate 2" "$OUT" "packages.x86_64-linux.dupapp"

echo
echo "CASE 5 — unknown machine fails loudly without prompting"
run_sut --dry-run --no-interactive --machine hwc-nosuchmachine fixtureapp; RC5=$RC
assert_eq "unknown machine exit code is 5" "5" "$RC5"
assert_contains "unknown machine lists what exists" "$OUT" "hwc-fixturehost"

echo
echo "CASE 6 — refuses to mutate main; diverts to a dedicated feature worktree"
BEFORE_MAIN="$(manifest "$WORKDIR/repo-main")"
OUT="$(cd "$WORKDIR/repo-main" && timeout 300 "$SUT" --no-interactive --no-commit \
        --no-build-test --machine hwc-fixturehost fixtureapp </dev/null 2>&1)"; RC6=$?
AFTER_MAIN="$(manifest "$WORKDIR/repo-main")"
assert_eq "main run exits 0" "0" "$RC6"
assert_contains "main run says it is refusing to write to main" "$OUT" "Refusing to write to 'main'"
assert_eq "main checkout is byte-identical afterwards" "$BEFORE_MAIN" "$AFTER_MAIN"
assert_eq "main checkout stays git-clean" "" "$(git -C "$WORKDIR/repo-main" status --porcelain)"
WT="$WORKDIR/.nixos-worktrees/fixtureapp"
assert_file "worktree holds the generated module" "$WT/domains/home/apps/fixtureapp/index.nix"
WTB="$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '<none>')"
assert_eq "worktree is on a dedicated branch" "add-app/fixtureapp" "$WTB"

echo
echo "CASE 7 — generates a current-shape mkSimpleApp module on a feature branch"
run_sut --no-interactive --no-commit --no-build-test --machine hwc-fixturehost fixtureapp; RC7=$RC
assert_eq "generation exits 0" "0" "$RC7"
APP="$REPO/domains/home/apps/fixtureapp"
assert_file "index.nix generated" "$APP/index.nix"
assert_no_file "no options.nix (Law 10)" "$APP/options.nix"
assert_file "per-app README generated" "$APP/README.md"
assert_no_file "profiles/home.nix never created" "$REPO/profiles/home.nix"
IDX="$(cat "$APP/index.nix" 2>/dev/null)"
assert_contains "index.nix uses the mkSimpleApp producer" "$IDX" "import ../../../lib/mkSimpleApp.nix"
assert_contains "index.nix names the app" "$IDX" 'name = "fixtureapp"'
assert_contains "index.nix selects the package" "$IDX" "pkgs.fixtureapp"
assert_not_contains "index.nix declares no raw mkOption" "$IDX" "mkOption"
RDM="$(cat "$APP/README.md" 2>/dev/null)"
for s in "## Purpose" "## Boundaries" "## Structure" "## Changelog"; do
  assert_contains "per-app README has $s" "$RDM" "$s"
done
APPS_RDM="$(cat "$REPO/domains/home/apps/README.md" 2>/dev/null)"
assert_contains "apps README structure lists the app" "$APPS_RDM" "├── fixtureapp/"
assert_contains "apps README changelog mentions the app" "$APPS_RDM" "fixtureapp"
MACHINE="$(cat "$REPO/machines/fixturehost/home.nix" 2>/dev/null)"
assert_contains "machine home.nix enables the app" "$MACHINE" "fixtureapp.enable = true;"
assert_contains "machine home.nix keeps the existing app" "$MACHINE" "existingapp.enable = true;"
if command -v nix-instantiate >/dev/null 2>&1; then
  nix-instantiate --parse "$APP/index.nix" >/dev/null 2>&1 \
    && ok "generated index.nix parses as Nix" || bad "generated index.nix parses as Nix"
  nix-instantiate --parse "$REPO/machines/fixturehost/home.nix" >/dev/null 2>&1 \
    && ok "edited machine home.nix parses as Nix" || bad "edited machine home.nix parses as Nix"
fi

echo
echo "CASE 8 — generates a Law-6 native adapter for a programs.<name> app"
run_sut --no-interactive --no-commit --no-build-test --machine hwc-fixturehost hmnative; RC8=$RC
assert_eq "native generation exits 0" "0" "$RC8"
NAPP="$REPO/domains/home/apps/hmnative"
assert_file "native index.nix generated" "$NAPP/index.nix"
assert_no_file "native has no options.nix (Law 10)" "$NAPP/options.nix"
NIDX="$(cat "$NAPP/index.nix" 2>/dev/null)"
assert_contains "native adapter declares its own enable option" "$NIDX" \
  "options.hwc.home.apps.hmnative"
assert_contains "native adapter delegates to programs.hmnative" "$NIDX" \
  "programs.hmnative.enable = true;"
assert_contains "native adapter has a VALIDATION assertion (Law 6)" "$NIDX" "assertions = ["
assert_not_contains "native adapter does not use mkSimpleApp" "$NIDX" "mkSimpleApp"
if command -v nix-instantiate >/dev/null 2>&1; then
  nix-instantiate --parse "$NAPP/index.nix" >/dev/null 2>&1 \
    && ok "generated native index.nix parses as Nix" || bad "generated native index.nix parses as Nix"
fi

echo
echo "CASE 9 — commit stages only the generated paths"
git -C "$REPO" checkout -q -- . 2>/dev/null || true
git -C "$REPO" clean -qfd 2>/dev/null || true
printf '\n# unrelated dirty edit\n' >> "$REPO/domains/home/apps/existingapp/README.md"
run_sut --no-interactive --no-build-test --machine hwc-fixturehost fixtureapp; RC9=$RC
assert_eq "committing run exits 0" "0" "$RC9"
COMMITTED="$(git -C "$REPO" show --name-only --pretty=format: HEAD | sed '/^$/d' | sort | tr '\n' ' ')"
assert_not_contains "unrelated dirty file stayed out of the commit" "$COMMITTED" \
  "domains/home/apps/existingapp/README.md"
assert_contains "commit carries the new module" "$COMMITTED" \
  "domains/home/apps/fixtureapp/index.nix"
assert_contains "commit carries the machine enable" "$COMMITTED" \
  "machines/fixturehost/home.nix"

echo
echo "-----------------------------------------------------------------"
printf 'passed: %d   failed: %d\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  printf 'failing cases:\n'
  for c in "${FAILED_CASES[@]}"; do printf '  - %s\n' "$c"; done
  exit 1
fi
echo "ALL PASS"
