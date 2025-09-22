#!/usr/bin/env bash
# HWC Charter v7 Linter
#
# WHAT IT CHECKS (strict, but tunable):
#   - Aggregators are named index.nix (no default.nix) under modules/**
#   - Each unit keeps options ONLY in options.nix (not index.nix/sys.nix/parts/*)
#   - parts/* are pure fragments (no options/imports/config)
#   - Home-lane purity vs. system writes (allow co-located modules/home/**/sys.nix)
#   - No Home Manager lane content under server/**
#   - Profiles discipline: machines import profiles only (not modules directly)
#   - HM activation only in profiles/home.nix (sanctioned exception)
#   - Single reverse-proxy authority (best-effort conflict check)
#   - Users must be defined only under modules/system/users/**
#   - Secrets hygiene (.age references and key material)
#   - .nix permissions are 0644
#
# TRIAGE MODE (environment variables):
#   HWC_LINT_RULES   = "all" (default) or comma list:
#                      aggregator_naming,options_presence,options_outside,parts_pure,
#                      lane_server,home_no_sys_writes,hm_profile,machines_profiles_only,
#                      profile_order,proxy_singleton,users_scope,secrets,permissions
#   HWC_LINT_CHANGED = 0|1  -> 1 = restrict to .nix files changed vs HWC_LINT_REF
#   HWC_LINT_REF     = git ref for CHANGED (default: origin/main)
#   HWC_LINT_PATHS   = space-separated subpaths to limit scans (e.g. "modules/server/containers")
#
# EXAMPLES:
#   # Full repo, all rules:
#   tools/hwc-lint.sh
#
#   # Only core rules while refactoring:
#   HWC_LINT_RULES="options_outside,parts_pure,permissions,hm_profile" tools/hwc-lint.sh
#
#   # Only changed files vs origin/main:
#   HWC_LINT_CHANGED=1 tools/hwc-lint.sh
#
#   # Focus just server containers, all rules:
#   HWC_LINT_RULES=all HWC_LINT_PATHS="modules/server/containers" tools/hwc-lint.sh
#
# RECOMMENDED pre-commit hook:
#   printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'exec tools/hwc-lint.sh' > .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
#
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$REPO_ROOT"

# ---------- Config ----------
HWC_LINT_RULES="${HWC_LINT_RULES:-all}"
HWC_LINT_CHANGED="${HWC_LINT_CHANGED:-0}"
HWC_LINT_REF="${HWC_LINT_REF:-origin/main}"
HWC_LINT_PATHS="${HWC_LINT_PATHS:-}"

# Scan only .nix files; ignore common junk
BASE_GLOBS=(-g '**/*.nix' -g '!**/.direnv/**' -g '!**/result*' -g '!**/node_modules/**')

# Aggregators that are allowed to lack options.nix (top-level collectors)
ALLOW_INDEX_NO_OPTIONS=(
  "modules/home/index.nix"
  "modules/home/apps/index.nix"
  "modules/home/theme/index.nix"
  "modules/infrastructure/index.nix"
  "modules/security/index.nix"
  "modules/security/secrets/index.nix"
  "modules/server/index.nix"
  "modules/system/index.nix"
)

# ---------- Helpers ----------
ERRS=0
WARNS=0
fail(){ ERRS=$((ERRS+1)); printf 'ERROR: %s\n' "$*" >&2; }
warn(){ WARNS=$((WARNS+1)); printf 'WARN : %s\n' "$*"; }
note(){ printf 'note : %s\n' "$*"; }
has(){ command -v "$1" >/dev/null 2>&1; }

need_tools(){
  local miss=0
  for t in rg awk find stat xargs sed cut sort uniq wc perl; do
    has "$t" || { echo "Missing tool: $t" >&2; miss=1; }
  done
  [[ $miss -eq 0 ]] || exit 2
}

# Build ripgrep path filters based on CHANGED/PATHS
build_filters() {
  local -a filters=("${BASE_GLOBS[@]}")
  if [[ -n "${HWC_LINT_PATHS}" ]]; then
    # If user specified paths, restrict to those
    local p
    for p in ${HWC_LINT_PATHS}; do filters+=(-g "$p/**"); done
  fi
  if [[ "${HWC_LINT_CHANGED}" == "1" ]]; then
    mapfile -t changed < <(git diff --name-only "${HWC_LINT_REF}" -- | grep -E '\.nix$' || true)
    if ((${#changed[@]})); then
      # replace with explicit changed globs
      filters=()
      local f
      for f in "${changed[@]}"; do filters+=(-g "$f"); done
    else
      echo "note : no changed .nix files vs ${HWC_LINT_REF}"
      echo "----------------------------------------"
      echo "LINT RESULTS: 0 error(s), 0 warning(s)"
      exit 0
    fi
  fi
  printf '%s\n' "${filters[@]}"
}

# Rule selector
WANT=",$HWC_LINT_RULES,"
run_rule(){ # $1=name  $2=function
  if [[ "$HWC_LINT_RULES" == "all" || "$WANT" == *",$1,"* ]]; then
    "$2"
  fi
}

is_allowed_index_without_options(){
  local f="$1"
  for a in "${ALLOW_INDEX_NO_OPTIONS[@]}"; do
    [[ "$f" == "$a" ]] && return 0
  done
  return 1
}

list_index_files(){
  rg -n -l --no-ignore -S "${RG_FILTERS[@]}" -g 'modules/**/index.nix' || true
}

# ---------- Checks ----------
check_aggregator_naming(){ # aggregator_naming
  local hits
  hits=$(rg -n -l --no-ignore -S "${RG_FILTERS[@]}" -g 'modules/**/default.nix' || true)
  [[ -z "$hits" ]] || while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    fail "Aggregator must be index.nix, not default.nix → $f"
  done <<< "$hits"
}

check_options_presence_per_unit(){ # options_presence
  local idx; idx="$(list_index_files)"
  [[ -n "$idx" ]] || return 0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if is_allowed_index_without_options "$f"; then
      continue
    fi
    local dir; dir=$(dirname "$f")
    local nix_count
    nix_count=$(find "$dir" -maxdepth 1 -type f -name '*.nix' | wc -l | awk '{print $1}')
    if [[ -d "$dir/parts" || -f "$dir/sys.nix" || "$nix_count" -gt 1 ]]; then
      [[ -f "$dir/options.nix" ]] || fail "Missing options.nix next to index.nix → $dir/"
    fi
  done <<< "$idx"
}

check_no_options_declared_in_disallowed_files(){ # options_outside
  local hits
  hits=$(rg -n --no-ignore -S "${RG_FILTERS[@]}" \
    -e '(^|\s)options\.' \
    -g 'modules/**/index.nix' \
    -g 'modules/**/sys.nix' \
    -g 'modules/**/parts/*.nix' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    fail "Options declared outside options.nix → $l"
  done <<< "$hits"
}

check_parts_are_pure(){ # parts_pure
  local hits
  hits=$(rg -n --no-ignore -S "${RG_FILTERS[@]}" \
    -g 'modules/**/parts/*.nix' \
    -e '(^|\s)options\.' -e '^\s*imports\s*=' -e '^\s*config\s*=' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    fail "parts/* must be pure fragments (no options/imports/config) → $l"
  done <<< "$hits"
}

check_lane_purity_server(){ # lane_server
  local hits
  hits=$(rg -n --no-ignore -S "${RG_FILTERS[@]}" -g 'modules/server/**' \
    -e '(^|\s)home\.' -e '(^|\s)programs\.' -e 'home-manager' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    fail "Home Manager content under server/ (lane purity) → $l"
  done <<< "$hits"
}

check_home_has_no_system_writes(){ # home_no_sys_writes
  local hits
  hits=$(rg -n --no-ignore -S "${RG_FILTERS[@]}" -g 'modules/home/**' \
    -e '(^|\s)systemd\.services\.' -e '(^|\s)environment\.systemPackages' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    local file="${l%%:*}"
    if [[ "$file" =~ ^modules/home/.*/sys\.nix$ ]]; then
      continue
    fi
    fail "System-lane mutation found under modules/home/** → $l"
  done <<< "$hits"
}

check_profiles_hm_activation(){ # hm_profile
  local hits
  hits=$(rg -n --no-ignore -S "${RG_FILTERS[@]}" -g 'profiles/**/*.nix' \
    -e '(^|\s)home-manager\s*=' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    local file="${l%%:*}"
    if [[ "$file" != "profiles/home.nix" ]]; then
      fail "Home Manager activation found in profiles; only profiles/home.nix is allowed → $l"
    fi
  done <<< "$hits"
}

check_machines_import_profiles_only(){ # machines_profiles_only
  local files
  files=$(rg -n -l --no-ignore -S "${RG_FILTERS[@]}" -g 'machines/**/config.nix' || true)
  [[ -z "$files" ]] && return 0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if rg -n --no-ignore -S "${RG_FILTERS[@]}" '\.\./modules/' "$f" >/dev/null; then
      fail "Machine config imports modules directly; machines must import profiles only → $f"
    fi
  done <<< "$files"
}

check_profile_lane_imports_and_order(){ # profile_order
  for p in profiles/home.nix profiles/sys.nix; do
    [[ -f "$p" ]] || continue
    local first_opt first_impl
    first_opt=$(rg -n --no-ignore -S "${RG_FILTERS[@]}" '/options\.nix' "$p" | head -n1 | cut -d: -f1 || true)
    first_impl=$(rg -n --no-ignore -S "${RG_FILTERS[@]}" '/(index|sys)\.nix' "$p" | head -n1 | cut -d: -f1 || true)
    if [[ -z "$first_opt" ]]; then
      warn "$p does not explicitly import options.nix; ensure domain aggregators load options first."
    elif [[ -n "$first_impl" && "$first_impl" -lt "$first_opt" ]]; then
      fail "$p imports implementations before options (options must be imported first)"
    fi
  done
}

check_single_proxy_authority(){ # proxy_singleton
  [[ -f profiles/sys.nix ]] || return 0
  local host container
  host=$(rg -n --no-ignore -S "${RG_FILTERS[@]}" 'reverseProxy|_shared/caddy\.nix' profiles/sys.nix || true)
  container=$(rg -n --no-ignore -S "${RG_FILTERS[@]}" '\.\./modules/server/.*/caddy/(index|.*\.nix)' profiles/sys.nix || true)
  if [[ -n "$host" && -n "$container" ]]; then
    fail "Reverse proxy conflict: host proxy and containerized Caddy imported together in profiles/sys.nix"
  fi
}

check_users_defined_in_system_users_only(){ # users_scope
  local hits
  hits=$(rg -n --no-ignore -S "${RG_FILTERS[@]}" '(^|\s)users\.users\.' modules -g '!modules/system/users/**' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    fail "User definitions must live under modules/system/users/** → $l"
  done <<< "$hits"
}

check_permissions_nix_sources(){ # permissions
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

check_secrets_hygiene(){ # secrets
  local priv age_refs
  priv=$(rg -n --no-ignore -S \
    -e '-----BEGIN (AGE ENCRYPTED FILE|OPENSSH PRIVATE KEY|RSA PRIVATE KEY|ED25519 PRIVATE KEY)-----' \
    -g '!**/vendor/**' -g '!**/node_modules/**' || true)
  [[ -z "$priv" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    fail "Private key material committed → $l"
  done <<< "$priv"

  age_refs=$(rg -n --no-ignore -S "${RG_FILTERS[@]}" '\.age(["'\'']|$)' modules -g '!modules/security/**' || true)
  [[ -z "$age_refs" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    fail ".age referenced outside modules/security/** (units must use /run/agenix/*) → $l"
  done <<< "$age_refs"
}

# ---------- Run ----------
need_tools
note "Repo: $REPO_ROOT"
mapfile -t RG_FILTERS < <(build_filters)

run_rule aggregator_naming            check_aggregator_naming
run_rule options_presence             check_options_presence_per_unit
run_rule options_outside              check_no_options_declared_in_disallowed_files
run_rule parts_pure                   check_parts_are_pure
run_rule lane_server                  check_lane_purity_server
run_rule home_no_sys_writes           check_home_has_no_system_writes
run_rule hm_profile                   check_profiles_hm_activation
run_rule machines_profiles_only       check_machines_import_profiles_only
run_rule profile_order                check_profile_lane_imports_and_order
run_rule proxy_singleton              check_single_proxy_authority
run_rule users_scope                  check_users_defined_in_system_users_only
run_rule permissions                  check_permissions_nix_sources
run_rule secrets                      check_secrets_hygiene

echo "----------------------------------------"
echo "LINT RESULTS: $ERRS error(s), $WARNS warning(s)"
[[ $ERRS -eq 0 ]] || exit 1
exit 0
