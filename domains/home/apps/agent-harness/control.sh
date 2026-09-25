#!/usr/bin/env bash
set -euo pipefail

EXPECTED=${AGENT_HARNESS_EXPECTED_MANIFEST:?expected manifest is not configured}
SYSTEM_MANIFEST=${AGENT_HARNESS_SYSTEM_MANIFEST:-/etc/agent-harness-manifest.json}
STATE=${AGENT_STATE_DIR:-$HOME/.agent-state}
SOURCE=${AGENT_HARNESS_SOURCE:-$HOME/.claude-config}
NIXOS=${AGENT_HARNESS_NIXOS:-$HOME/.nixos}
FLEET=${AGENT_HARNESS_FLEET_HOSTS:?fleet hosts are not configured}
FLEET_HOSTS=()
STORE_PREFIX=${AGENT_HARNESS_STORE_PREFIX:-/nix/store}
SYSTEM_POLICY=${AGENT_HARNESS_SYSTEM_POLICY:-/etc/agent-harness/CLAUDE.md}
CLAUDE_INSTRUCTIONS=${AGENT_HARNESS_CLAUDE_INSTRUCTIONS:-$HOME/.claude/CLAUDE.md}
CODEX_HOOKS=${AGENT_HARNESS_CODEX_HOOKS:-$HOME/.codex/hooks.json}
CODEX_SKILL=${AGENT_HARNESS_CODEX_SKILL:-$HOME/.agents/skills/stepwise-refinement}
PI_INSTRUCTIONS=${AGENT_HARNESS_PI_INSTRUCTIONS:-$HOME/.pi/agent/AGENTS.md}
CLAUDE_SETTINGS=${AGENT_HARNESS_CLAUDE_SETTINGS:-/etc/claude-code/managed-settings.json}

failures=0
ok() { printf 'ok   %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*"; failures=$((failures + 1)); }

show_state_case() {
  local case_file="$STATE/.git/.sync-case.json"
  [ -r "$case_file" ] || return 0
  jq -r '"agent-state case: \(.state) (\(.lastOutcome), \(.caseId))"' "$case_file" 2>/dev/null || true
}

validate_fleet() {
  local host
  IFS=: read -r -a FLEET_HOSTS <<< "$FLEET"
  [ "${#FLEET_HOSTS[@]}" -gt 0 ] || { printf 'agent-harness: fleet is empty\n' >&2; return 1; }
  for host in "${FLEET_HOSTS[@]}"; do
    [[ "$host" =~ ^hwc-[a-z0-9-]+$ ]] || { printf 'agent-harness: invalid fleet host %s\n' "$host" >&2; return 1; }
  done
}

expected_revision() { jq -r '.staticPolicy.revision' "$EXPECTED"; }

check_command() {
  if command -v "$1" >/dev/null 2>&1; then ok "command $1"; else fail "command $1"; fi
}

check_store_path() {
  local label=$1 path=$2 resolved
  if [ ! -e "$path" ]; then fail "$label missing at $path"; return; fi
  resolved=$(readlink -f "$path")
  case "$resolved" in
    "$STORE_PREFIX"/*) ok "$label -> $resolved" ;;
    *) fail "$label resolves outside the Nix store: $resolved" ;;
  esac
}

check_no_authoring_reference() {
  local label=$1 path=$2
  if [ ! -r "$path" ]; then fail "$label missing at $path"; return; fi
  if rg -a -n -F "$SOURCE" "$path" >/dev/null; then
    fail "$label references mutable authoring source $SOURCE"
  else
    ok "$label has no mutable-source reference"
  fi
}

doctor_local() {
  failures=0
  if [ -r "$SYSTEM_MANIFEST" ] && cmp -s "$EXPECTED" "$SYSTEM_MANIFEST"; then
    ok 'system and user ownership manifests match'
  elif [ -r "$SYSTEM_MANIFEST" ]; then
    fail "system revision $(jq -r '.staticPolicy.revision // "missing"' "$SYSTEM_MANIFEST") != user revision $(expected_revision)"
  else
    fail "system ownership manifest missing at $SYSTEM_MANIFEST"
  fi

  check_store_path 'system policy' "$SYSTEM_POLICY"
  check_store_path 'Claude instructions' "$CLAUDE_INSTRUCTIONS"
  check_store_path 'Codex hooks' "$CODEX_HOOKS"
  check_store_path 'Codex workflow skill' "$CODEX_SKILL"
  check_store_path 'Pi instructions' "$PI_INSTRUCTIONS"
  check_no_authoring_reference 'Codex hooks' "$CODEX_HOOKS"
  check_no_authoring_reference 'Claude managed settings' "$CLAUDE_SETTINGS"
  if command -v t3-dx2-handoff >/dev/null 2>&1; then
    check_no_authoring_reference 'T3 DX2 handoff' "$(command -v t3-dx2-handoff)"
  fi

  if agent-state-validate >/dev/null; then
    ok 'mutable state ownership'
  else
    fail 'mutable state ownership'
    show_state_case
  fi
  if codex-hooks-trust --check >/dev/null; then ok 'Codex hooks trusted'; else fail 'Codex hooks untrusted or unverifiable'; fi
  if systemctl --user --quiet is-active agent-state-sync.timer; then ok 'agent-state-sync.timer active'; else fail 'agent-state-sync.timer inactive'; fi
  for command in claude codex pi herdr; do check_command "$command"; done

  if [ -d "$SOURCE/.git" ]; then
    if [ -n "$(git -C "$SOURCE" status --porcelain --untracked-files=no)" ]; then
      warn "static authoring source has unpublished tracked changes: $SOURCE"
    fi
    source_revision=$(git -C "$SOURCE" rev-parse HEAD)
    if [ "$source_revision" != "$(expected_revision)" ]; then
      warn "authoring source $source_revision differs from active revision $(expected_revision)"
    fi
  else
    warn "static authoring source is absent at $SOURCE"
  fi

  printf 'static revision: %s\n' "$(expected_revision)"
  return "$failures"
}

doctor_fleet() {
  local desired host output remote_revision fleet_failures=0
  validate_fleet
  desired=$(expected_revision)
  for host in "${FLEET_HOSTS[@]}"; do
    if [ "$host" = "$(hostname)" ]; then
      if ! doctor_local; then fleet_failures=$((fleet_failures + 1)); fi
      continue
    fi
    if ! output=$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$host" 'agent-harness revision && agent-harness doctor' 2>&1); then
      printf '%s\n' "$output"
      fail "fleet host $host failed doctor"
      fleet_failures=$((fleet_failures + 1))
      continue
    fi
    printf '%s\n' "$output"
    remote_revision=$(printf '%s\n' "$output" | awk 'NR == 1 { print; exit }')
    if [ "$remote_revision" != "$desired" ]; then
      fail "fleet host $host revision $remote_revision != desired $desired"
      fleet_failures=$((fleet_failures + 1))
    else
      ok "fleet host $host revision $remote_revision"
    fi
  done
  [ "$fleet_failures" -eq 0 ]
}

require_clean_tracked() {
  local repo=$1 label=$2
  [ -d "$repo/.git" ] || { printf 'agent-harness: %s repo missing at %s\n' "$label" "$repo" >&2; return 1; }
  [ -z "$(git -C "$repo" status --porcelain --untracked-files=no)" ] || {
    printf 'agent-harness: %s has tracked changes; commit them first\n' "$label" >&2
    return 1
  }
}

publish_preflight() {
  validate_fleet
  require_clean_tracked "$SOURCE" 'static policy'
  require_clean_tracked "$NIXOS" 'nixos-hwc'
  [ "$(git -C "$SOURCE" branch --show-current)" = main ] || { printf 'agent-harness: static policy must be on main\n' >&2; return 1; }
  [ "$(git -C "$NIXOS" branch --show-current)" = main ] || { printf 'agent-harness: nixos-hwc must be on main\n' >&2; return 1; }

  (cd "$SOURCE" && bin/harness-policy-check)
  git -C "$SOURCE" fetch github refs/heads/main:refs/remotes/github/main
  git -C "$SOURCE" merge-base --is-ancestor github/main HEAD || { printf 'agent-harness: static policy is behind github/main\n' >&2; return 1; }

  git -C "$NIXOS" fetch origin refs/heads/main:refs/remotes/origin/main
  [ "$(git -C "$NIXOS" rev-parse HEAD)" = "$(git -C "$NIXOS" rev-parse origin/main)" ] || {
    printf 'agent-harness: nixos-hwc main must equal origin/main before publication\n' >&2
    return 1
  }

  static_revision=$(git -C "$SOURCE" rev-parse HEAD)
  locked=$(jq -r '.nodes."agent-harness".locked.rev' "$NIXOS/flake.lock")
  if [ "$locked" = "$static_revision" ]; then
    ok "nixos-hwc already pins static revision $static_revision"
  else
    ok "nixos-hwc will update static revision $locked -> $static_revision"
  fi
}

publish() {
  case "${1:-}" in
    ''|--check) ;;
    *) usage ;;
  esac
  publish_preflight
  [ "${1:-}" != --check ] || return 0

  git -C "$SOURCE" push github HEAD:main
  static_revision=$(git -C "$SOURCE" rev-parse HEAD)

  if [ "$locked" != "$static_revision" ]; then
    (cd "$NIXOS" && nix flake update agent-harness)
    [ "$(jq -r '.nodes."agent-harness".locked.rev' "$NIXOS/flake.lock")" = "$static_revision" ] || {
      printf 'agent-harness: flake lock did not resolve static revision %s\n' "$static_revision" >&2
      return 1
    }
    git -C "$NIXOS" add flake.lock
    git -C "$NIXOS" commit -m "chore: publish agent harness $static_revision"
  fi

  local host
  for host in "${FLEET_HOSTS[@]}"; do
    nix build --no-link "$NIXOS#nixosConfigurations.$host.config.system.build.toplevel"
  done
  git -C "$NIXOS" push origin main

  for host in "${FLEET_HOSTS[@]}"; do
    if [ "$host" = "$(hostname)" ]; then
      sudo nixos-rebuild switch --flake "$NIXOS#$host"
    else
      ssh -t "$host" "cd ~/.nixos && git pull --ff-only && sudo nixos-rebuild switch --flake .#$host"
    fi
  done
  exec "$BASH" "$0" doctor --fleet
}

usage() {
  printf 'usage: agent-harness [status|doctor [--fleet]|revision|sync|validate-state|diff|publish [--check]]\n' >&2
  exit 2
}

command=${1:-}
if [ -z "$command" ] && [ -t 0 ]; then
  printf '1 status\n2 doctor\n3 fleet doctor\n4 sync\n5 validate state\n6 static diff\n7 publish\n> '
  read -r choice
  case "$choice" in
    1) command=status ;; 2) command=doctor ;; 3) command=doctor; set -- doctor --fleet ;;
    4) command=sync ;; 5) command=validate-state ;; 6) command="diff" ;; 7) command=publish ;; *) exit 2 ;;
  esac
fi

case "$command" in
  status)
    systemctl --user show agent-state-sync.timer -p ActiveState -p SubState -p LastTriggerUSec --no-pager
    show_state_case
    git -C "$STATE" status --short --branch
    ;;
  doctor) if [ "${2:-}" = --fleet ]; then doctor_fleet; else doctor_local; fi ;;
  revision) expected_revision ;;
  sync) exec agent-state-sync sync ;;
  validate-state) exec agent-state-validate ;;
  diff) git --no-pager diff --no-index /etc/agent-harness "$SOURCE" || [ "$?" = 1 ] ;;
  publish) publish "${2:-}" ;;
  *) usage ;;
esac
