#!/usr/bin/env bash
# HWC Charter Compliance Linter v10.1
# Validates against Charter v10.1 Architectural Laws
# Usage: ./workspace/nixos/charter-lint.sh [--fix] [--verbose] [domain]

set -Eeuo pipefail
IFS=$'\n\t'

# Colors
readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m' CYAN='\033[0;36m' NC='\033[0m'

# Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
find_repo_root() {
  local dir="$SCRIPT_DIR"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/domains" && -d "$dir/profiles" && -f "$dir/flake.nix" ]]; then
      printf "%s" "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  printf "${RED}[ERROR]${NC} Could not locate repository root (missing domains/, profiles/, or flake.nix)\n" >&2
  exit 1
}
readonly REPO_ROOT="$(find_repo_root)"
readonly PERMISSION_LINT="$REPO_ROOT/workspace/utilities/lints/permission-lint.sh"
readonly TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hwc-charter.XXXXXX")"
KEEP_LOGS="${KEEP_LOGS:-1}"
cleanup() { [[ "$KEEP_LOGS" == "1" ]] || rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Flags & Counters
VERBOSE=false
FIX_MODE=false
DOMAIN_FILTER=""
TOTAL_VIOLATIONS=0
declare -A LAW_COUNTS=(
  [1]=0 [2]=0 [3]=0 [4]=0 [5]=0 [6]=0 [7]=0 [8]=0 [9]=0 [10]=0
)
declare -A LAW_NAMES=(
  [1]="Handshake (home osConfig guard)"
  [2]="Namespace fidelity"
  [3]="Path abstraction"
  [4]="Permission model"
  [5]="mkContainer standard"
  [6]="Three sections & validation"
  [7]="sys.nix lane purity"
  [8]="Data retention contract"
  [9]="Filesystem materialization discipline"
  [10]="Primitive module exception"
)
declare -A LAW_HINTS=(
  [1]="Add osConfig ? {} to home module args; guard osConfig.* and assertions with isNixOS."
  [2]="Align option namespaces to folder paths; remove hwc.services/hwc.features prefixes; keep options in options.nix."
  [3]="Replace hardcoded /mnt|/home/eric|/opt with config.hwc.paths.* values (except in paths.nix)."
  [4]="Run permission-lint fixes: PUID=1000/PGID=100, services run as eric:users, secrets group with 0440."
  [5]="Wrap containers with mkContainer helper; justify any direct oci-containers.* usage."
  [6]="Ensure index.nix has # OPTIONS/# IMPLEMENTATION/# VALIDATION and assertions are mkIf cfg.enable; move options to options.nix."
  [7]="Do not import sys.nix from home index; keep system-only logic in sys.nix and avoid home->system references."
  [8]="Document retention policy and add cleanup timer for persistent volumes (retain/retention/cleanup.timer)."
  [9]="Materialize core directories only in domains/system/core/filesystem.nix via tmpfiles."
  [10]="Only domains/paths/paths.nix may co-locate options and implementation; keep exception scoped."
)
declare -A LAW_LOGS
for i in {1..10}; do
  LAW_LOGS[$i]="$TMP_DIR/law-$i.log"
  : > "${LAW_LOGS[$i]}"
done

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
log()     { printf "${BLUE}[LINT]${NC} %s\n" "$1"; }
error()   { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; ((TOTAL_VIOLATIONS++)) || true; return 0; }
warn()    { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
success() { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
debug()   { [[ "$VERBOSE" == "true" ]] && printf "${PURPLE}[DEBUG]${NC} %s\n" "$1" >&2 || true; }
fail_law() {
  local law="$1" msg="$2" file="${3:-}"
  local log_file="${LAW_LOGS[$law]}"
  [[ -n "$file" ]] && msg="${msg} (file: ${file#$REPO_ROOT/})"
  echo "- $msg" >> "$log_file"
  if [[ "$VERBOSE" == "true" ]]; then
    printf "${RED}[LAW %s]${NC} %s\n" "$law" "$msg" >&2
  fi
  ((LAW_COUNTS[$law]++)) || true
  ((TOTAL_VIOLATIONS++)) || true
  return 0
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { error "Required command missing: $1"; exit 127; }
}
require_cmd rg find grep sed mktemp

matches_domain_filter() {
  local path="$1"
  [[ -z "$DOMAIN_FILTER" ]] && return 0
  case "$DOMAIN_FILTER" in
    home|system|server|infrastructure) [[ "$path" == *"/domains/$DOMAIN_FILTER"* ]] ;;
    profiles) [[ "$path" == *"/profiles/"* ]] ;;
    machines) [[ "$path" == *"/machines/"* ]] ;;
    *) return 1 ;;
  esac
}

run_rg_to_file() {
  # Wrapper to avoid set -e exits when rg finds nothing
  local outfile="$1"; shift
  if rg "$@" >"$outfile" 2>"$TMP_DIR/rg.err"; then
    return 0
  fi
  local code=$?
  if [[ $code -eq 1 ]]; then
    return 1
  fi
  cat "$TMP_DIR/rg.err" >&2
  return $code
}

# ------------------------------------------------------------
# Argument Parsing
# ------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix) FIX_MODE=true; shift ;;
    --verbose|-v) VERBOSE=true; shift ;;
    --help|-h)
      printf "Usage: %s [--fix] [--verbose] [domain]\n" "$0"
      printf "  domain: home|system|server|infrastructure|profiles|machines\n"
      exit 0
      ;;
    home|system|server|infrastructure|profiles|machines)
      DOMAIN_FILTER="$1"; shift ;;
    *) error "Unknown arg: $1"; exit 1 ;;
  esac
done

[[ -n "$DOMAIN_FILTER" ]] && log "Filtering to domain: $DOMAIN_FILTER"

# ------------------------------------------------------------
# Law 1: Handshake Protocol
# ------------------------------------------------------------
check_law1_handshake() {
  log "Law 1: Checking osConfig handshake in home domain..."

  while IFS= read -r file; do
    matches_domain_filter "$file" || continue
    # Skip data-only files (first non-comment line must start with a lambda)
    first_line="$(sed -n '/^[[:space:]]*[^#[:space:]]/ {p; q}' "$file")"
    [[ "$first_line" =~ ^\{ ]] || continue
    [[ "$first_line" == *":"* ]] || continue
    if ! grep -qE 'osConfig\s*\?\s*\{' "$file"; then
      fail_law 1 "Missing optional osConfig = {} in signature" "$file"
    fi
  done < <(find "$REPO_ROOT/domains/home" -name "*.nix" -type f || true)

  local all_osconfig="$TMP_DIR/osconfig-all.txt"
  local unguarded="$TMP_DIR/osconfig-unguarded.txt"
  if run_rg_to_file "$all_osconfig" 'osConfig\.' "$REPO_ROOT/domains/home" --type nix --glob '!*.md' --glob '!*.org'; then
    rg -v '(?i)(or false|\?|\bor null|\? hwc|isNixOS|mkIf isNixOS)' "$all_osconfig" >"$unguarded" || true
    if [[ -s "$unguarded" ]]; then
      cat "$unguarded" >> "${LAW_LOGS[1]}"
      if [[ "$VERBOSE" == "true" ]]; then
        cat "$unguarded"
      fi
      fail_law 1 "Unguarded osConfig access detected" ""
    fi
  fi
  return 0
}

# ------------------------------------------------------------
# Law 2: Namespace Fidelity
# ------------------------------------------------------------
check_law2_namespace() {
  log "Law 2: Checking namespace fidelity & deprecated prefixes..."

  local ns_path="$REPO_ROOT/domains"
  case "$DOMAIN_FILTER" in
    home|system|server|infrastructure) ns_path="$REPO_ROOT/domains/$DOMAIN_FILTER" ;;
  esac

  local deprecated="$TMP_DIR/deprecated-ns.txt"
  if run_rg_to_file "$deprecated" 'hwc\.services\.|hwc\.features\.' "$ns_path" --type nix; then
    if [[ -s "$deprecated" ]]; then
      cat "$deprecated" >> "${LAW_LOGS[2]}"
      [[ "$VERBOSE" == "true" ]] && cat "$deprecated"
      fail_law 2 "Deprecated namespace (hwc.services.* or hwc.features.*) detected" ""
    fi
  fi

  local options_outside="$TMP_DIR/options-outside.txt"
  if run_rg_to_file "$options_outside" 'options\.hwc\.' "$ns_path" --type nix --glob '!options.nix' --glob '!sys.nix' --glob '!paths/paths.nix'; then
    if [[ -s "$options_outside" ]]; then
      cat "$options_outside" >> "${LAW_LOGS[2]}"
      [[ "$VERBOSE" == "true" ]] && cat "$options_outside"
      fail_law 2 "Options defined outside options.nix (Law 2/6 violation)" ""
    fi
  fi
  return 0
}

# ------------------------------------------------------------
# Law 3: Path Abstraction Contract
# ------------------------------------------------------------
check_law3_paths() {
  log "Law 3: Checking for hardcoded paths..."
  local hits="$TMP_DIR/hardcoded.txt"
  local filtered="$TMP_DIR/hardcoded-filtered.txt"
  if run_rg_to_file "$hits" '="/mnt/|="/home/eric/|="/opt/' "$REPO_ROOT/domains" \
      --glob '!paths.nix' --glob '!*.md' --glob '!*.org'; then
    rg -v '^\s*#' "$hits" | rg -v 'example\s*=' >"$filtered" || true
    if [[ -s "$filtered" ]]; then
      cat "$filtered" >> "${LAW_LOGS[3]}"
      [[ "$VERBOSE" == "true" ]] && cat "$filtered"
      fail_law 3 "Hardcoded path detected (see output)" ""
    fi
  fi
  return 0
}

# ------------------------------------------------------------
# Law 4: Permission Model
# ------------------------------------------------------------
check_law4_permissions() {
  log "Law 4: Running permission linter..."
  if [[ -n "$DOMAIN_FILTER" && "$DOMAIN_FILTER" != "server" ]]; then
    debug "Skipping permission linter for domain filter: $DOMAIN_FILTER"
    return 0
  fi
  if [[ -x "$PERMISSION_LINT" ]]; then
    local perm_log="${LAW_LOGS[4]}"
    if ! "$PERMISSION_LINT" >"$perm_log" 2>&1; then
      [[ "$VERBOSE" == "true" ]] && cat "$perm_log"
      fail_law 4 "Permission model violation (see permission-lint output)" ""
    fi
  else
    warn "Permission linter script not found/executable: $PERMISSION_LINT"
  fi
  return 0
}

# ------------------------------------------------------------
# Law 5: mkContainer Standard
# ------------------------------------------------------------
check_law5_mkcontainer() {
  log "Law 5: Checking container definitions use mkContainer..."
  if [[ -n "$DOMAIN_FILTER" && "$DOMAIN_FILTER" != "server" ]]; then
    debug "Skipping Law 5 for domain filter: $DOMAIN_FILTER"
    return 0
  fi
  local raw="$TMP_DIR/raw-containers.txt"
  if run_rg_to_file "$raw" 'virtualisation\.oci-containers\.containers\.[^=]+=' "$REPO_ROOT/domains/server" \
      --glob '!_shared/pure.nix' --glob '!mkContainer' --glob '!*.md'; then
    if [[ -s "$raw" ]]; then
      cat "$raw" >> "${LAW_LOGS[5]}"
      [[ "$VERBOSE" == "true" ]] && cat "$raw"
      fail_law 5 "Raw oci-containers block without mkContainer (Law 5 violation)" ""
    fi
  fi
  return 0
}

# ------------------------------------------------------------
# Law 6: Three Sections & Validation Discipline
# ------------------------------------------------------------
check_law6_three_sections() {
  log "Law 6: Checking three-section pattern in index.nix..."
  while IFS= read -r file; do
    matches_domain_filter "$file" || continue

    grep -q "#\s*OPTIONS" "$file" || fail_law 6 "Missing # OPTIONS section" "$file"
    grep -q "#\s*IMPLEMENTATION" "$file" || fail_law 6 "Missing # IMPLEMENTATION section" "$file"
    if ! grep -q "#\s*VALIDATION" "$file"; then
      warn "No # VALIDATION section (optional if no deps)" "$file"
    fi

    if grep -q "options\.hwc" "$file" && [[ ! "$file" =~ options\.nix$ ]]; then
      fail_law 6 "Options defined outside options.nix" "$file"
    fi

    if grep -q "assertions\s*=" "$file" && ! grep -q "mkIf.*enable" "$file"; then
      fail_law 6 "Unguarded assertions (not under mkIf cfg.enable)" "$file"
    fi
  done < <(find "$REPO_ROOT/domains" -name "index.nix" -type f || true)
  return 0
}

# ------------------------------------------------------------
# Law 7: sys.nix Lane Purity
# ------------------------------------------------------------
check_law7_sys_purity() {
  log "Law 7: Checking sys.nix lane purity..."

  local import_sys="$TMP_DIR/home-import-sys.txt"
  if run_rg_to_file "$import_sys" 'import.*sys\.nix' "$REPO_ROOT/domains/home" --glob '*/index.nix'; then
    if [[ -s "$import_sys" ]]; then
      cat "$import_sys" >> "${LAW_LOGS[7]}"
      [[ "$VERBOSE" == "true" ]] && cat "$import_sys"
      fail_law 7 "Home index.nix imports sys.nix (lane violation)" ""
    fi
  fi

  local systemd_home="$TMP_DIR/systemd-home.txt"
  if run_rg_to_file "$systemd_home" 'systemd\.services' "$REPO_ROOT/domains/home" --glob '!sys.nix'; then
    if [[ -s "$systemd_home" ]]; then
      cat "$systemd_home" >> "${LAW_LOGS[7]}"
      [[ "$VERBOSE" == "true" ]] && cat "$systemd_home"
      fail_law 7 "systemd.services in home domain outside sys.nix" ""
    fi
  fi
  return 0
}

# ------------------------------------------------------------
# Law 8: Data Retention Contract
# ------------------------------------------------------------
check_law8_retention() {
  log "Law 8: Checking for retention policies on persistent data..."
  local volumes="$TMP_DIR/volumes.txt"
  local missing="$TMP_DIR/retention-missing.txt"

  if run_rg_to_file "$volumes" 'volumes.*=/media|/config|/state' "$REPO_ROOT/domains/server" --type nix; then
    rg -L 'retain:|retention:|cleanup.timer|days:|find.*-mtime' "$volumes" >"$missing" || true
    if [[ -s "$missing" ]]; then
      cat "$missing" >> "${LAW_LOGS[8]}"
      [[ "$VERBOSE" == "true" ]] && cat "$missing"
      fail_law 8 "Persistent volume without retention/timer detected (heuristic)" ""
    fi
  fi
  return 0
}

# ------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------
main() {
  log "HWC Charter v10.1 Compliance Linter"
  log "Repo root: $REPO_ROOT"

  check_law1_handshake
  check_law2_namespace
  check_law3_paths
  check_law4_permissions
  check_law5_mkcontainer
  check_law6_three_sections
  check_law7_sys_purity
  check_law8_retention

  printf "\n${BLUE}Summary:${NC}\n"
  for i in {1..10}; do
    count=${LAW_COUNTS[$i]}
    local name="${LAW_NAMES[$i]}"
    local log_file="${LAW_LOGS[$i]}"
    if [[ $count -gt 0 ]]; then
      printf "  Law %d (%s): ${RED}%d violation(s)${NC}\n" "$i" "$name" "$count"
      if [[ -s "$log_file" ]]; then
        local max=5
        printf "    Samples (first %d):\n" "$max"
        head -n "$max" "$log_file" | sed 's/^/      /'
        local total_lines
        total_lines=$(wc -l < "$log_file" | tr -d ' ')
        if [[ $total_lines -gt $max ]]; then
          printf "      ... (%d more) use --verbose to see all\n" "$((total_lines - max))"
        fi
      fi
    else
      printf "  Law %d (%s): ${GREEN}0 violation(s)${NC}\n" "$i" "$name"
    fi
  done

  if [[ $TOTAL_VIOLATIONS -eq 0 ]]; then
    success "All laws compliant! ✓"
  else
    error "Found $TOTAL_VIOLATIONS violation(s) across laws."
    printf "  Logs: %s/law-<n>.log (e.g., %s)\n" "$TMP_DIR" "${LAW_LOGS[1]}"
    printf "  Tips: run with --verbose for full listings; focus on highest law counts first.\n"
    printf "  Cleanup: set KEEP_LOGS=0 to auto-remove temp logs after run.\n"
    printf "\n${BLUE}Next steps:${NC}\n"
    # Show top three offending laws with hints
    for law in $(for i in {1..10}; do printf "%s:%s\n" "${LAW_COUNTS[$i]}" "$i"; done | sort -t: -k1,1nr | head -3 | awk -F: '$1>0 {print $2}'); do
      printf "  Law %s: %s\n" "$law" "${LAW_HINTS[$law]}"
    done
    exit 1
  fi
}

main "$@"
