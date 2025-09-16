#!/usr/bin/env bash
# HWC Charter v7 Linter
# Enforces: single API (options.nix), lane purity, aggregator naming, import discipline,
# profiles-only machines, one proxy authority, secrets hygiene, permissions, and more.

set -euo pipefail

# -------- config --------
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$REPO_ROOT"

DOMAINS=(modules/home modules/infrastructure modules/security modules/server modules/system)

# Known aggregators that are allowed to NOT have options.nix next to index.nix
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

# -------- helpers --------
ERRS=0
WARNS=0
fail(){ ERRS=$((ERRS+1)); printf 'ERROR: %s\n' "$*" >&2; }
warn(){ WARNS=$((WARNS+1)); printf 'WARN : %s\n' "$*"; }
note(){ printf 'note : %s\n' "$*"; }
has(){ command -v "$1" >/dev/null 2>&1; }

need_tools(){
  local miss=0
  for t in rg awk find stat xargs sed cut sort uniq; do
    has "$t" || { echo "Missing tool: $t" >&2; miss=1; }
  done
  [[ $miss -eq 0 ]] || exit 2
}

is_allowed_index_without_options(){
  local f="$1"
  for a in "${ALLOW_INDEX_NO_OPTIONS[@]}"; do
    [[ "$f" == "$a" ]] && return 0
  done
  return 1
}

list_index_files(){
  rg -n -l --no-ignore -S \
    -g 'modules/**/index.nix' \
    -g '!**/.direnv/**' -g '!**/result*' -g '!**/node_modules/**' || true
}

# -------- checks --------

check_aggregator_naming(){
  local hits
  hits=$(rg -n -l --no-ignore -S -g 'modules/**/default.nix' || true)
  [[ -z "$hits" ]] || while IFS= read -r f; do
    fail "Aggregator must be index.nix, not default.nix → $f"
  done <<< "$hits"
}

check_options_presence_per_unit(){
  # Require options.nix next to index.nix for unit directories (not domain aggregators)
  local idx
  idx="$(list_index_files)"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if is_allowed_index_without_options "$f"; then
      continue
    fi
    # Heuristic: if directory looks like a unit (has parts/ or sys.nix or other files),
    # it must have options.nix
    local dir; dir=$(dirname "$f")
    if [[ -d "$dir/parts" || -f "$dir/sys.nix" || $(find "$dir" -maxdepth 1 -type f -name '*.nix' | wc -l) -gt 1 ]]; then
      [[ -f "$dir/options.nix" ]] || fail "Missing options.nix next to index.nix → $dir/ (single API per unit)"
    fi
  done <<< "$idx"
}

check_no_options_declared_in_disallowed_files(){
  # options.* must only live in options.nix (not in index.nix, sys.nix, parts/*)
  local hits
  hits=$(rg -n --no-ignore -S \
    -e '(^|\s)options\.' \
    -g 'modules/**/index.nix' \
    -g 'modules/**/sys.nix' \
    -g 'modules/**/parts/*.nix' || true)
  [[ -z "$hits" ]] || while IFS= read -r line; do
    fail "Options declared outside options.nix → $line"
  done <<< "$hits"
}

check_lane_purity(){
  # No HM lane content under server/**
  local hits
  hits=$(rg -n --no-ignore -S -g 'modules/server/**' \
    -e '(^|\s)home\.' \
    -e '(^|\s)programs\.' \
    -e 'home-manager' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    fail "Home Manager content under server/ (lane purity) → $l"
  done <<< "$hits"
}

check_profiles_do_not_activate_hm(){
  # HM activation must be machine-specific, not in profiles
  local hits
  hits=$(rg -n --no-ignore -S -g 'profiles/**/*.nix' -e '(^|\s)home-manager\s*=' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    fail "Home Manager activation found in profiles; must be in machines/*/home.nix → $l"
  done <<< "$hits"
}

check_machines_import_profiles_only(){
  # machines/*/config.nix must not import modules directly
  local files
  files=$(rg -n -l --no-ignore -S -g 'machines/**/config.nix' || true)
  [[ -z "$files" ]] || while IFS= read -r f; do
    if rg -n --no-ignore -S '\.\./modules/' "$f" >/dev/null; then
      fail "Machine config imports modules directly; machines must import profiles only → $f"
    fi
  done <<< "$files"
}

check_profile_lane_imports_and_order(){
  # profiles/hm.nix must not import server/*/index.nix
  [[ -f profiles/hm.nix ]] && if rg -n --no-ignore -S '\.\./modules/server/.*/index\.nix' profiles/hm.nix >/dev/null; then
    fail "profiles/hm.nix imports server/*/index.nix (lane cross-import)"
  fi
  # profiles/sys.nix must not import home/*/index.nix
  [[ -f profiles/sys.nix ]] && if rg -n --no-ignore -S '\.\./modules/home/.*/index\.nix' profiles/sys.nix >/dev/null; then
    fail "profiles/sys.nix imports home/*/index.nix (lane cross-import)"
  fi
  # Import order: options before implementations in each profile
  for p in profiles/hm.nix profiles/sys.nix; do
    [[ -f "$p" ]] || continue
    local first_opt first_impl
    first_opt=$(rg -n --no-ignore -S '/options\.nix' "$p" | head -n1 | cut -d: -f1 || true)
    first_impl=$(rg -n --no-ignore -S '/(index|sys)\.nix' "$p" | head -n1 | cut -d: -f1 || true)
    if [[ -z "$first_opt" ]]; then
      warn "$p does not explicitly import options.nix; ensure domain aggregators load options first."
    elif [[ -n "$first_impl" && "$first_impl" -lt "$first_opt" ]]; then
      fail "$p imports implementations before options (options must be imported first)"
    fi
  done
}

check_single_proxy_authority(){
  # profiles/sys.nix importing both host Caddy aggregator and container Caddy unit → error
  [[ -f profiles/sys.nix ]] || return 0
  local host container
  host=$(rg -n --no-ignore -S 'reverseProxy|_shared/caddy\.nix|server/.*/_shared/caddy\.nix' profiles/sys.nix || true)
  container=$(rg -n --no-ignore -S '\.\./modules/server/.*/caddy/(index|.*\.nix)' profiles/sys.nix || true)
  if [[ -n "$host" && -n "$container" ]]; then
    fail "Reverse proxy conflict: host Caddy aggregator and containerized Caddy imported together in profiles/sys.nix"
  fi
}

check_permissions_nix_sources(){
  # All tracked *.nix must be 0644
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

check_secrets_hygiene(){
  # No private keys; .age references only in modules/security/**
  local priv
  priv=$(rg -n --no-ignore -S \
    -e '-----BEGIN (AGE ENCRYPTED FILE|OPENSSH PRIVATE KEY|RSA PRIVATE KEY|ED25519 PRIVATE KEY)-----' \
    -g '!**/vendor/**' -g '!**/node_modules/**' || true)
  [[ -z "$priv" ]] || while IFS= read -r l; do
    fail "Private key material committed → $l"
  done <<< "$priv"

  local age_refs
  age_refs=$(rg -n --no-ignore -S '\.age(["'\'']|$)' modules -g '!modules/security/**' || true)
  [[ -z "$age_refs" ]] || while IFS= read -r l; do
    fail ".age referenced outside modules/security/** (units must use /run/agenix/*) → $l"
  done <<< "$age_refs"
}

check_parts_are_pure(){
  # parts/*.nix must not declare options/imports or top-level config
  local hits
  hits=$(rg -n --no-ignore -S \
    -g 'modules/**/parts/*.nix' \
    -e '(^|\s)options\.' -e '^\s*imports\s*=' -e '^\s*config\s*=' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    fail "parts/* must be pure fragments (no options/imports/config) → $l"
  done <<< "$hits"
}

check_users_defined_in_system_users_only(){
  # users.users.* must only appear under modules/system/users/**
  local hits
  hits=$(rg -n --no-ignore -S '(^|\s)users\.users\.' -g '!modules/system/users/**' modules || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    fail "User definitions must live under modules/system/users/** → $l"
  done <<< "$hits"
}

check_home_has_no_system_writes(){
  # No systemd.services or environment.systemPackages under modules/home/**
  local hits
  hits=$(rg -n --no-ignore -S -g 'modules/home/**' \
    -e '(^|\s)systemd\.services\.' \
    -e '(^|\s)environment\.systemPackages' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    fail "System-lane mutation found under modules/home/** → $l"
  done <<< "$hits"
}

# -------- run --------
need_tools
note "Repo: $REPO_ROOT"

check_aggregator_naming
check_options_presence_per_unit
check_no_options_declared_in_disallowed_files
check_lane_purity
check_profiles_do_not_activate_hm
check_machines_import_profiles_only
check_profile_lane_imports_and_order
check_single_proxy_authority
check_permissions_nix_sources
check_secrets_hygiene
check_parts_are_pure
check_users_defined_in_system_users_only
check_home_has_no_system_writes

echo "----------------------------------------"
echo "LINT RESULTS: $ERRS error(s), $WARNS warning(s)"
[[ $ERRS -eq 0 ]] || exit 1
exit 0
