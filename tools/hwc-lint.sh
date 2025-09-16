#!/usr/bin/env bash
# HWC Charter v7 Linter (focused & reliable)
#
# PURPOSE
#   Fast, deterministic lint for the core HWC charter rules that matter during refactors.
#   Uses narrow file scopes and explicit allowlists to reduce false positives.
#
# WHAT IT CHECKS (tunable via HWC_LINT_RULES):
#   - aggregator_naming:   Aggregators are named index.nix (no default.nix) under modules/**
#   - options_outside:     No `options.*` in index.nix / sys.nix / parts/*  (must live in options.nix)
#   - parts_pure:          parts/* contain only fragments (no `options`, no top-level `imports =`, no top-level `config =`)
#   - hm_profile:          Only profiles/hm.nix may contain `home-manager =`
#   - users_scope:         All users.users.* must live under modules/system/users/**
#   - permissions:         All *.nix must be mode 0644
#
# USAGE
#   # Full repo, all rules:
#   tools/hwc-lint.sh
#
#   # Only specific rules:
#   HWC_LINT_RULES="options_outside,parts_pure,permissions" tools/hwc-lint.sh
#
#   # Only changed files vs origin/main:
#   HWC_LINT_CHANGED=1 tools/hwc-lint.sh
#
#   # Limit scan to a subtree:
#   HWC_LINT_PATHS="modules/server/containers modules/home/apps/waybar" tools/hwc-lint.sh
#
# ENV
#   HWC_LINT_RULES   = all (default) or comma-list of rule names
#   HWC_LINT_CHANGED = 0|1  (restrict to changed files vs HWC_LINT_REF)
#   HWC_LINT_REF     = git ref (default: origin/main)
#   HWC_LINT_PATHS   = space-separated subpaths to include
#
# EXIT
#   0 on clean; 1 if any errors; 2 if required tools missing.
#
set -euo pipefail

# ---------- Setup ----------
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$REPO_ROOT"

HWC_LINT_RULES="${HWC_LINT_RULES:-all}"
HWC_LINT_CHANGED="${HWC_LINT_CHANGED:-0}"
HWC_LINT_REF="${HWC_LINT_REF:-origin/main}"
HWC_LINT_PATHS="${HWC_LINT_PATHS:-}"

# Tools check
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing tool: $1" >&2; exit 2; }; }
need rg; need awk; need find; need stat; need sed; need cut; need sort; need uniq; need wc

# File scopes
BASE_GLOBS=(-g '**/*.nix' -g '!**/.direnv/**' -g '!**/result*' -g '!**/node_modules/**')
if [[ -n "$HWC_LINT_PATHS" ]]; then
  PATH_GLOBS=()
  for p in $HWC_LINT_PATHS; do PATH_GLOBS+=(-g "$p/**"); done
else
  PATH_GLOBS=()
fi

# Only changed?
if [[ "$HWC_LINT_CHANGED" == "1" ]]; then
  mapfile -t CHANGED < <(git diff --name-only "$HWC_LINT_REF" -- | rg -n '^.*\.nix$' -N -S || true)
  if ((${#CHANGED[@]}==0)); then
    echo "note : no changed .nix files vs ${HWC_LINT_REF}"
    echo "----------------------------------------"
    echo "LINT RESULTS: 0 error(s), 0 warning(s)"
    exit 0
  fi
  RG_SCOPE=()
  for f in "${CHANGED[@]}"; do RG_SCOPE+=(-g "$f"); done
else
  RG_SCOPE=("${PATH_GLOBS[@]}" "${BASE_GLOBS[@]}")
fi

ERRS=0; WARNS=0
fail(){ ERRS=$((ERRS+1)); printf 'ERROR: %s\n' "$*" >&2; }
warn(){ WARNS=$((WARNS+1)); printf 'WARN : %s\n' "$*"; }
note(){ printf 'note : %s\n' "$*"; }

note "Repo: $REPO_ROOT"

# ---------- Helpers ----------
WANT=",$HWC_LINT_RULES,"
run_rule(){ # $1=name  $2=function
  if [[ "$HWC_LINT_RULES" == "all" || "$WANT" == *",$1,"* ]]; then
    "$2"
  fi
}

# ---------- Rules ----------
check_aggregator_naming(){ # aggregator_naming
  local hits
  hits=$(rg -n -l --no-ignore -S "${RG_SCOPE[@]}" -g 'modules/**/default.nix' || true)
  [[ -z "$hits" ]] || while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    fail "Aggregator must be index.nix, not default.nix → $f"
  done <<< "$hits"
}

check_options_outside(){ # options_outside
  # Only flag options.* if it appears in files where it's disallowed.
  # Allowed: **/options.nix only.
  local hits
  hits=$(rg -n --no-ignore -S "${RG_SCOPE[@]}" \
      -g 'modules/**/index.nix' \
      -g 'modules/**/sys.nix' \
      -g 'modules/**/parts/*.nix' \
      -e '(^|\s)options\.' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    fail "Options declared outside options.nix → $l"
  done <<< "$hits"
}

check_parts_pure(){ # parts_pure
  # Only scan files under parts/*.nix, never elsewhere.
  # Parts must NOT declare top-level options/imports/config blocks.
  local hits
  hits=$(rg -n --no-ignore -S "${RG_SCOPE[@]}" \
      -g 'modules/**/parts/*.nix' \
      -e '^\s*options\.' -e '^\s*imports\s*=' -e '^\s*config\s*=' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    fail "parts/* must be pure fragments (no options/imports/config) → $l"
  done <<< "$hits"
}

check_hm_profile(){ # hm_profile
  # Only profiles/hm.nix may contain 'home-manager ='
  local hits
  hits=$(rg -n --no-ignore -S "${RG_SCOPE[@]}" \
      -g 'profiles/**/*.nix' -e '(^|\s)home-manager\s*=' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    local file="${l%%:*}"
    if [[ "$file" != "profiles/hm.nix" ]]; then
      fail "Home Manager activation found in profiles; only profiles/hm.nix is allowed → $l"
    fi
  done <<< "$hits"
}

check_users_scope(){ # users_scope
  # All users.users.* must live under modules/system/users/**
  # Only scan *.nix (no README/md).
  local hits
  hits=$(rg -n --no-ignore -S "${RG_SCOPE[@]}" \
      -g 'modules/**/*.nix' -g '!modules/system/users/**' \
      -e '(^|\s)users\.users\.' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    fail "User definitions must live under modules/system/users/** → $l"
  done <<< "$hits"
}

check_permissions(){ # permissions
  local bad=0
  while IFS= read -r -d '' f; do
    local mode; mode=$(stat -c '%a' "$f")
    if [[ "$mode" != "644" ]]; then
      fail "Permissions must be 0644 for Nix sources → $f (mode $mode)"
      bad=1
    fi
  done < <(find modules profiles machines -type f -name '*.nix' ! -path '*/.direnv/*' -print0 2>/dev/null || true)
  return $bad
}

# ---------- Run ----------
run_rule aggregator_naming   check_aggregator_naming
run_rule options_outside     check_options_outside
run_rule parts_pure          check_parts_pure
run_rule hm_profile          check_hm_profile
run_rule users_scope         check_users_scope
run_rule permissions         check_permissions

echo "----------------------------------------"
echo "LINT RESULTS: $ERRS error(s), $WARNS warning(s)"
[[ $ERRS -eq 0 ]] || exit 1
exit 0
