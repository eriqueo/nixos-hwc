#!/usr/bin/env bash
set -euo pipefail

EXPECTED=${AGENT_HARNESS_EXPECTED_MANIFEST:?expected manifest is not configured}
SYSTEM_MANIFEST=${AGENT_HARNESS_SYSTEM_MANIFEST:-/etc/agent-harness-manifest.json}
STATE=${AGENT_STATE_DIR:-$HOME/800_agents/state}
SOURCE=${AGENT_HARNESS_SOURCE:-$HOME/.claude-config}
NIXOS=${AGENT_HARNESS_NIXOS:-$HOME/.nixos}
FLEET=${AGENT_HARNESS_FLEET_HOSTS:?fleet hosts are not configured}
FLEET_HOSTS=()
STORE_PREFIX=${AGENT_HARNESS_STORE_PREFIX:-/nix/store}
SYSTEM_POLICY=${AGENT_HARNESS_SYSTEM_POLICY:-/etc/agent-harness/CLAUDE.md}
CLAUDE_INSTRUCTIONS=${AGENT_HARNESS_CLAUDE_INSTRUCTIONS:-$HOME/.claude/CLAUDE.md}
CODEX_HOOKS=${AGENT_HARNESS_CODEX_HOOKS:-$HOME/.codex/hooks.json}
PI_INSTRUCTIONS=${AGENT_HARNESS_PI_INSTRUCTIONS:-$HOME/.pi/agent/AGENTS.md}
PI_SETTINGS=${AGENT_HARNESS_PI_SETTINGS:-$HOME/.pi/agent/settings.json}
CLAUDE_SETTINGS=${AGENT_HARNESS_CLAUDE_SETTINGS:-/etc/claude-code/managed-settings.json}
# The one skill set (a store path) and the roots every runtime reads it from.
SKILL_SET=${AGENT_HARNESS_SKILL_SET:-}
SKILL_ROOTS=${AGENT_HARNESS_SKILL_ROOTS:-}
CODEX_SKILLS=${AGENT_HARNESS_CODEX_SKILLS:-$HOME/.codex/skills}
NOTIFY_URL=${AGENT_HARNESS_NOTIFY_URL:-}

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

# Content fingerprint of the skill set. Hosts on different nixpkgs build the
# same content at different store paths, so the fleet compares this instead.
skill_fingerprint() {
  (cd "$SKILL_SET" && find -L . -type f -print0 | sort -z | xargs -0 sha256sum) \
    | sha256sum | cut -c1-16
}

check_skills() {
  local root resolved entry path roots extra=()
  if [ -z "$SKILL_SET" ] || [ -z "$SKILL_ROOTS" ]; then fail 'skill set or roots not configured'; return; fi
  IFS=: read -r -a roots <<< "$SKILL_ROOTS"
  for root in "${roots[@]}"; do
    resolved=$(readlink -f "$root" 2>/dev/null || true)
    if [ "$resolved" = "$SKILL_SET" ]; then ok "skill root $root"; else fail "skill root $root -> ${resolved:-missing}, not the shared set $SKILL_SET"; fi
  done
  # Codex keeps this root writable for its own .system; anything else here is
  # a hand install that only Codex would see.
  if [ -d "$CODEX_SKILLS" ]; then
    for entry in "$CODEX_SKILLS"/*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      extra+=("$(basename "$entry")")
    done
  fi
  if [ "${#extra[@]}" -eq 0 ]; then ok "$CODEX_SKILLS holds only Codex built-ins"; else fail "$CODEX_SKILLS has hand-installed skills: ${extra[*]} (add them to the shared set instead)"; fi
  if [ -r "$PI_SETTINGS" ]; then
    while IFS= read -r path; do
      resolved=$(readlink -f "${path/#\~/$HOME}" 2>/dev/null || true)
      if [ "$resolved" = "$SKILL_SET" ]; then ok "Pi skill path $path"; else fail "Pi skill path $path is not the shared set"; fi
    done < <(jq -r '.skills[]? // empty' "$PI_SETTINGS")
  else
    fail "Pi settings missing at $PI_SETTINGS"
  fi
  printf 'skill fingerprint: %s (%s skills)\n' "$(skill_fingerprint)" \
    "$(find "$SKILL_SET" -mindepth 1 -maxdepth 1 -type d | wc -l)"
}

doctor_local() {
  failures=0
  check_skills
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
  local desired host output remote_revision remote_skills fleet_failures=0
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
    remote_skills=$(printf '%s\n' "$output" | awk '/^skill fingerprint: / { print $3; exit }')
    if [ "$remote_skills" != "$(skill_fingerprint)" ]; then
      fail "fleet host $host skill set ${remote_skills:-unreported} != this host's $(skill_fingerprint)"
      fleet_failures=$((fleet_failures + 1))
    else
      ok "fleet host $host skill set matches"
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
  # Remote authoring checkouts track the server mirror, while Nix pins GitHub.
  # Publish both before switching, so the checkout and active policy agree.
  git -C "$SOURCE" push origin HEAD:main
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

  # Build each host in its own store: evaluate here, realise there. A remote
  # host already holds its heavy closure, so nothing is fetched twice. Measured
  # 2026-09-30: building hwc-home on hwc-work refetched its CUDA archives from
  # NVIDIA, and a dropped download failed the whole publication twice.
  local host
  for host in "${FLEET_HOSTS[@]}"; do
    if [ "$host" = "$(hostname)" ]; then
      nix build --no-link "$NIXOS#nixosConfigurations.$host.config.system.build.toplevel"
    else
      nix build --no-link --eval-store auto --store "ssh-ng://$host" \
        "$NIXOS#nixosConfigurations.$host.config.system.build.toplevel"
    fi
  done
  git -C "$NIXOS" push origin main

  for host in "${FLEET_HOSTS[@]}"; do
    if [ "$host" = "$(hostname)" ]; then
      sudo nixos-rebuild switch --flake "$NIXOS#$host"
    else
      ssh -t "$host" "git -C ~/.claude-config pull --ff-only && cd ~/.nixos && git pull --ff-only && sudo nixos-rebuild switch --flake .#$host"
    fi
  done
  # The CLI now on PATH, not "$0": this process is the pre-switch store copy,
  # whose expected manifest still names the old revision, so re-running it
  # reported every freshly switched host as a mismatch (2026-09-30).
  exec agent-harness doctor --fleet
}

# The hourly timer: the doctor's FAIL lines are the case, and an alert goes out
# only when the case changes, so lasting drift alerts once (the
# agent-cli-update pattern). The case is recorded only after its alert is sent.
drift() {
  local out current previous case_file title body
  case_file="${XDG_STATE_HOME:-$HOME/.local/state}/agent-harness/drift"
  mkdir -p "$(dirname "$case_file")"
  out=$(doctor_local 2>&1) || true
  printf '%s\n' "$out"
  current=$(printf '%s\n' "$out" | awk '/^FAIL / { sub(/^FAIL /, ""); print }')
  previous=$(cat "$case_file" 2>/dev/null || true)
  [ "$current" = "$previous" ] && { [ -z "$current" ]; return; }
  if [ -n "$current" ]; then
    title="Agent harness drift on $(hostname)"
    body="$current"$'\n'"Check: agent-harness doctor"
  else
    title="Agent harness drift cleared on $(hostname)"
    body="agent-harness doctor is clean again. No action needed."
  fi
  if [ -n "$NOTIFY_URL" ] && jq -n --arg t "$title" --arg b "$body" \
      '{topic:"monitoring",title:$t,body:$b,priority:2,source:"agent-harness-drift"}' \
      | curl -fsS --max-time 5 -H 'content-type: application/json' -d @- "$NOTIFY_URL" >/dev/null 2>&1; then
    printf '%s' "$current" > "$case_file"
  fi
  [ -z "$current" ]
}

usage() {
  printf 'usage: agent-harness [status|doctor [--fleet]|drift|revision|sync|validate-state|diff|publish [--check]]\n' >&2
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
  drift) drift ;;
  revision) expected_revision ;;
  sync) exec agent-state-sync sync ;;
  validate-state) exec agent-state-validate ;;
  diff) git --no-pager diff --no-index /etc/agent-harness "$SOURCE" || [ "$?" = 1 ] ;;
  publish) publish "${2:-}" ;;
  *) usage ;;
esac
