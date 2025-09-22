#!/usr/bin/env bash
# HWC Charter v7 Linter (focused & reliable)
#
# PURPOSE
#   Fast, deterministic lint for core HWC charter rules, with low false-positives.
#
# CHECKS (tunable via HWC_LINT_RULES):
#   - aggregator_naming : no modules/**/default.nix (aggregators must be index.nix)
#   - options_outside   : forbid "options.*" in index.nix / sys.nix / parts/*.nix (never options.nix)
#   - parts_pure        : forbid top-level "options.", "imports =", "config =" in parts/*.nix
#   - hm_profile        : only profiles/home.nix may contain "home-manager ="
#   - users_scope       : "users.users.*" only under modules/system/users/** (ignores comments)
#   - permissions       : all *.nix must be mode 0644
#
# USAGE
#   tools/hwc-lint.sh
#   HWC_LINT_RULES="options_outside,parts_pure,permissions" tools/hwc-lint.sh
#   HWC_LINT_CHANGED=1 tools/hwc-lint.sh
#   HWC_LINT_PATHS="modules/server/containers modules/home/apps/waybar" tools/hwc-lint.sh
#
# ENV
#   HWC_LINT_RULES   = all (default) or comma-list of rule names
#   HWC_LINT_CHANGED = 0|1  (changed files vs HWC_LINT_REF)
#   HWC_LINT_REF     = git ref (default: origin/main)
#   HWC_LINT_PATHS   = space-separated subpaths to include
#
# EXIT: 0 clean, 1 errors, 2 missing tools
set -euo pipefail

# ---------- Setup ----------
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$REPO_ROOT"

HWC_LINT_RULES="${HWC_LINT_RULES:-all}"
HWC_LINT_CHANGED="${HWC_LINT_CHANGED:-0}"
HWC_LINT_REF="${HWC_LINT_REF:-origin/main}"
HWC_LINT_PATHS="${HWC_LINT_PATHS:-}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing tool: $1" >&2; exit 2; }; }
need rg; need awk; need find; need stat; need sed; need cut; need sort; need uniq; need wc

# ripgrep PCRE2 is required for comment-ignoring
if ! rg -P -V >/dev/null 2>&1; then
  echo "Missing PCRE2-enabled ripgrep (-P). Install rg with PCRE2 support." >&2
  exit 2
fi

# Glob scopes
BASE_GLOBS=(-g '**/*.nix' -g '!**/.direnv/**' -g '!**/result*' -g '!**/node_modules/**')
PATH_GLOBS=()
if [[ -n "$HWC_LINT_PATHS" ]]; then
  for p in $HWC_LINT_PATHS; do PATH_GLOBS+=(-g "$p/**"); done
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
  # Flag ONLY real option declarations outside options.nix.
  # - Restrict to these files: index.nix, sys.nix, parts/*.nix
  # - Explicitly exclude options.nix anywhere
  # - Ignore commented lines
  local hits
  hits=$(rg -n --no-ignore -P "${RG_SCOPE[@]}" \
      -g 'modules/**/index.nix' \
      -g 'modules/**/sys.nix' \
      -g 'modules/**/parts/*.nix' \
      -g '!**/options.nix' \
      -e '^(?!\s*#).*?\boptions\.' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    fail "Options declared outside options.nix → $l"
  done <<< "$hits"
}

check_parts_pure(){ # parts_pure
  # Parts must NOT define top-level options/imports/config.
  # - Only scan parts/*.nix
  # - Ignore commented lines
  local hits
  hits=$(rg -n --no-ignore -P "${RG_SCOPE[@]}" \
      -g 'modules/**/parts/*.nix' \
      -e '^(?!\s*#)\s*options\.' \
      -e '^(?!\s*#)\s*imports\s*=' \
      -e '^(?!\s*#)\s*config\s*=' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    fail "parts/* must be pure fragments (no options/imports/config) → $l"
  done <<< "$hits"
}

check_hm_profile(){ # hm_profile
  # Only profiles/home.nix may contain 'home-manager ='
  # Ignore commented lines
  local hits
  hits=$(rg -n --no-ignore -P "${RG_SCOPE[@]}" \
      -g 'profiles/**/*.nix' \
      -e '^(?!\s*#).*?\bhome-manager\s*=' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    local file="${l%%:*}"
    if [[ "$file" != "profiles/home.nix" ]]; then
      fail "Home Manager activation found in profiles; only profiles/home.nix is allowed → $l"
    fi
  done <<< "$hits"
}

check_users_scope(){ # users_scope
  # Only allow users.users.* in modules/system/users/**
  # - Ignore commented lines
  local hits
  hits=$(rg -n --no-ignore -P "${RG_SCOPE[@]}" \
      -g 'machines/**/*.nix' -g 'modules/**/*.nix' \
      -g '!modules/system/users/**' \
      -e '^(?!\s*#).*?\busers\.users\.' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    # Allow root credential mutations ONLY inside modules/security/**
    local file="${l%%:*}"
    if [[ "$file" == modules/security/* ]] && echo "$l" | rg -q -P '\busers\.users\.root\.(hashedPassword(File)?|password(File)?|initialPassword)\b'; then
      continue
    fi
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
