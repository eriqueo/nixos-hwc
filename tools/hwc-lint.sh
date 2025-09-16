#!/usr/bin/env bash
# HWC Charter v7 Linter (rev2)
# - Single API per unit (options.nix)
# - Lane purity
# - Aggregator naming (index.nix only)
# - Profiles discipline (machines import profiles only)
# - HM activation: ONLY allowed in profiles/hm.nix (sanctioned exception)
# - Parts purity (no options/imports/config)
# - One proxy authority (best-effort)
# - .nix permissions 0644
# - Secrets hygiene
# Notes:
# * Scans ONLY .nix files (avoids README/MD false positives)
# * Allows co-located Home sys.nix
# * Guards ripgrep calls to avoid "no pattern" noise

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$REPO_ROOT"

DOMAINS=(modules/home modules/infrastructure modules/security modules/server modules/system)
ONLY_NIX_GLOBS=(-g '**/*.nix' -g '!**/.direnv/**' -g '!**/result*' -g '!**/node_modules/**')

# index.nix without options.nix is allowed ONLY for these aggregators
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

ERRS=0
WARNS=0
fail(){ ERRS=$((ERRS+1)); printf 'ERROR: %s\n' "$*" >&2; }
warn(){ WARNS=$((WARNS+1)); printf 'WARN : %s\n' "$*"; }
note(){ printf 'note : %s\n' "$*"; }
has(){ command -v "$1" >/dev/null 2>&1; }

need_tools(){
  local miss=0
  for t in rg awk find stat xargs sed cut sort uniq wc; do
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
  rg -n -l --no-ignore -S "${ONLY_NIX_GLOBS[@]}" -g 'modules/**/index.nix' || true
}

# ---------- Checks ----------

check_aggregator_naming(){
  # forbid default.nix as an aggregator anywhere under modules/**
  local hits
  hits=$(rg -n -l --no-ignore -S "${ONLY_NIX_GLOBS[@]}" -g 'modules/**/default.nix' || true)
  [[ -z "$hits" ]] || while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    fail "Aggregator must be index.nix, not default.nix → $f"
  done <<< "$hits"
}

check_options_presence_per_unit(){
  local idx; idx="$(list_index_files)"
  [[ -n "$idx" ]] || return 0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if is_allowed_index_without_options "$f"; then
      continue
    fi
    local dir; dir=$(dirname "$f")
    # If it looks like a unit (has parts/, sys.nix, or >1 nix files), require options.nix
    local count nix_count
    nix_count=$(find "$dir" -maxdepth 1 -type f -name '*.nix' | wc -l | awk '{print $1}')
    if [[ -d "$dir/parts" || -f "$dir/sys.nix" || "$nix_count" -gt 1 ]]; then
      [[ -f "$dir/options.nix" ]] || fail "Missing options.nix next to index.nix → $dir/"
    fi
  done <<< "$idx"
}

check_no_options_declared_in_disallowed_files(){
  # options.* must live ONLY in options.nix (not in index.nix, sys.nix, parts/*.nix)
  local hits
  hits=$(rg -n --no-ignore -S "${ONLY_NIX_GLOBS[@]}" \
    -e '(^|\s)options\.' \
    -g 'modules/**/index.nix' \
    -g 'modules/**/sys.nix' \
    -g 'modules/**/parts/*.nix' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    fail "Options declared outside options.nix → $l"
  done <<< "$hits"
}

check_lane_purity_server(){
  # No HM lane config under server/** (nix files only)
  local hits
  hits=$(rg -n --no-ignore -S "${ONLY_NIX_GLOBS[@]}" -g 'modules/server/**' \
    -e '(^|\s)home\.' -e '(^|\s)programs\.' -e 'home-manager' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    fail "Home Manager content under server/ (lane purity) → $l"
  done <<< "$hits"
}

check_profiles_hm_activation(){
  # HM activation only allowed in profiles/hm.nix
  local profs hits
  profs=$(rg -n -l --no-ignore -S "${ONLY_NIX_GLOBS[@]}" -g 'profiles/**/*.nix' || true)
  [[ -z "$profs" ]] && return 0
  hits=$(rg -n --no-ignore -S "${ONLY_NIX_GLOBS[@]}" -g 'profiles/**/*.nix' -e '(^|\s)home-manager\s*=' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    local file="${l%%:*}"
    if [[ "$file" != "profiles/hm.nix" ]]; then
      fail "Home Manager activation found in profiles; only profiles/hm.nix is allowed → $l"
    fi
  done <<< "$hits"
}

check_machines_import_profiles_only(){
  # machines/*/config.nix must not import modules directly
  local files
  files=$(rg -n -l --no-ignore -S "${ONLY_NIX_GLOBS[@]}" -g 'machines/**/config.nix' || true)
  [[ -z "$files" ]] && return 0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if rg -n --no-ignore -S "${ONLY_NIX_GLOBS[@]}" '\.\./modules/' "$f" >/dev/null; then
      fail "Machine config imports modules directly; machines must import profiles only → $f"
    fi
  done <<< "$files"
}

check_profile_lane_imports_and_order(){
  # Warn if profiles don't import options before implementations (best-effort)
  for p in profiles/hm.nix profiles/sys.nix; do
    [[ -f "$p" ]] || continue
    local first_opt first_impl
    first_opt=$(rg -n --no-ignore -S "${ONLY_NIX_GLOBS[@]}" '/options\.nix' "$p" | head -n1 | cut -d: -f1 || true)
    first_impl=$(rg -n --no-ignore -S "${ONLY_NIX_GLOBS[@]}" '/(index|sys)\.nix' "$p" | head -n1 | cut -d: -f1 || true)
    if [[ -z "$first_opt" ]]; then
      warn "$p does not explicitly import options.nix; ensure domain aggregators load options first."
    elif [[ -n "$first_impl" && "$first_impl" -lt "$first_opt" ]]; then
      fail "$p imports implementations before options (options must be imported first)"
    fi
  done
}

check_single_proxy_authority(){
  # Very best-effort: error if profiles/sys.nix references both host-proxy and server/container caddy
  [[ -f profiles/sys.nix ]] || return 0
  local host container
  host=$(rg -n --no-ignore -S "${ONLY_NIX_GLOBS[@]}" 'reverseProxy|_shared/caddy\.nix|server/.*/_shared/caddy\.nix' profiles/sys.nix || true)
  container=$(rg -n --no-ignore -S "${ONLY_NIX_GLOBS[@]}" '\.\./modules/server/.*/caddy/(index|.*\.nix)' profiles/sys.nix || true)
  if [[ -n "$host" && -n "$container" ]]; then
    fail "Reverse proxy conflict: host proxy and containerized Caddy imported together in profiles/sys.nix"
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
  # No private key material in repo; .age referenced only in modules/security/**
  local priv age_refs
  priv=$(rg -n --no-ignore -S \
    -e '-----BEGIN (AGE ENCRYPTED FILE|OPENSSH PRIVATE KEY|RSA PRIVATE KEY|ED25519 PRIVATE KEY)-----' \
    -g '!**/vendor/**' -g '!**/node_modules/**' || true)
  [[ -z "$priv" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    fail "Private key material committed → $l"
  done <<< "$priv"

  age_refs=$(rg -n --no-ignore -S "${ONLY_NIX_GLOBS[@]}" '\.age(["'\'']|$)' modules -g '!modules/security/**' || true)
  [[ -z "$age_refs" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    fail ".age referenced outside modules/security/** (units must use /run/agenix/*) → $l"
  done <<< "$age_refs"
}

check_parts_are_pure(){
  # parts/*.nix must not declare options/imports/config
  local hits
  hits=$(rg -n --no-ignore -S "${ONLY_NIX_GLOBS[@]}" \
    -g 'modules/**/parts/*.nix' \
    -e '(^|\s)options\.' -e '^\s*imports\s*=' -e '^\s*config\s*=' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    fail "parts/* must be pure fragments (no options/imports/config) → $l"
  done <<< "$hits"
}

check_users_defined_in_system_users_only(){
  # users.users.* must appear only under modules/system/users/** (allowlist: emergency root if you decide later)
  local hits
  hits=$(rg -n --no-ignore -S "${ONLY_NIX_GLOBS[@]}" '(^|\s)users\.users\.' modules -g '!modules/system/users/**' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    fail "User definitions must live under modules/system/users/** → $l"
  done <<< "$hits"
}

check_home_has_no_system_writes(){
  # No systemd.services or environment.systemPackages under modules/home/**,
  # EXCEPT co-located sys.nix files (explicitly allowed) and pure fragments.
  local hits
  hits=$(rg -n --no-ignore -S "${ONLY_NIX_GLOBS[@]}" -g 'modules/home/**' \
    -e '(^|\s)systemd\.services\.' -e '(^|\s)environment\.systemPackages' || true)
  [[ -z "$hits" ]] || while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    local file="${l%%:*}"
    # allow co-located sys.nix under modules/home/**
    if [[ "$file" =~ ^modules/home/.*/sys\.nix$ ]]; then
      continue
    fi
    fail "System-lane mutation found under modules/home/** → $l"
  done <<< "$hits"
}

# ---------- Run ----------

need_tools
note "Repo: $REPO_ROOT"

check_aggregator_naming
check_options_presence_per_unit
check_no_options_declared_in_disallowed_files
check_lane_purity_server
check_profiles_hm_activation
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
