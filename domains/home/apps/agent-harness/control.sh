#!/usr/bin/env bash
set -euo pipefail

EXPECTED=${AGENT_HARNESS_EXPECTED_MANIFEST:?expected manifest is not configured}
SYSTEM_MANIFEST=${AGENT_HARNESS_SYSTEM_MANIFEST:-/etc/agent-harness-manifest.json}
STATE=${AGENT_STATE_DIR:-$HOME/800_agents/state}
SOURCE=${AGENT_HARNESS_SOURCE:-$HOME/800_agents/harness}
NIXOS=${AGENT_HARNESS_NIXOS:-$HOME/.nixos}
FLEET=${AGENT_HARNESS_FLEET_HOSTS:?fleet hosts are not configured}
FLEET_HOSTS=()
STORE_PREFIX=${AGENT_HARNESS_STORE_PREFIX:-/nix/store}
SYSTEM_POLICY=${AGENT_HARNESS_SYSTEM_POLICY:-/etc/agent-harness/rules/AGENTS.md}
HARNESS_ROOT=${AGENT_HARNESS_ROOT:-/etc/agent-harness}
CLAUDE_INSTRUCTIONS=${AGENT_HARNESS_CLAUDE_INSTRUCTIONS:-$HOME/.claude/CLAUDE.md}
CODEX_HOOKS=${AGENT_HARNESS_CODEX_HOOKS:-$HOME/.codex/hooks.json}
PI_INSTRUCTIONS=${AGENT_HARNESS_PI_INSTRUCTIONS:-$HOME/.pi/agent/AGENTS.md}
PI_SETTINGS=${AGENT_HARNESS_PI_SETTINGS:-$HOME/.pi/agent/settings.json}
PI_HOOK_BRIDGE=${AGENT_HARNESS_PI_HOOK_BRIDGE:-$HOME/.pi/agent/extensions/hwc-hook-bridge.ts}
PI_BRIDGE_FAILURES=${AGENT_HARNESS_PI_BRIDGE_FAILURES:-$HOME/.local/state/agent-harness/pi-bridge-failures.log}
CLAUDE_SETTINGS=${AGENT_HARNESS_CLAUDE_SETTINGS:-/etc/claude-code/managed-settings.json}
# The one skill set (a store path) and the roots every runtime reads it from.
SKILL_SET=${AGENT_HARNESS_SKILL_SET:-}
SKILL_ROOTS=${AGENT_HARNESS_SKILL_ROOTS:-}
CODEX_SKILLS=${AGENT_HARNESS_CODEX_SKILLS:-$HOME/.codex/skills}
NOTIFY_URL=${AGENT_HARNESS_NOTIFY_URL:-}
# manifest.toml's [matrix] and [outside], as JSON from Nix.
MATRIX=${AGENT_HARNESS_MATRIX:-}
CLAUDE_HOME=${AGENT_HARNESS_CLAUDE_HOME:-$HOME/.claude}
CLAUDE_MCP=${AGENT_HARNESS_CLAUDE_MCP:-$HOME/.mcp.json}
CODEX_INSTRUCTIONS=${AGENT_HARNESS_CODEX_INSTRUCTIONS:-$HOME/.codex/AGENTS.md}

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
  (cd "$SKILL_SET" && find -L . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) \
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
  # Pi reaches the shared hooks only through this extension; a failure to run
  # them is logged by it, and blocks Pi's bash/write/edit calls meanwhile.
  check_store_path 'Pi hook bridge' "$PI_HOOK_BRIDGE"
  local since recent=0
  since=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)
  if [ -r "$PI_BRIDGE_FAILURES" ]; then
    recent=$(awk -F'\t' -v s="$since" '$1 >= s' "$PI_BRIDGE_FAILURES" | wc -l)
  fi
  if [ "$recent" -eq 0 ]; then ok 'Pi hook bridge: no failures in the last hour'; else fail "Pi hook bridge failed $recent time(s) in the last hour: $PI_BRIDGE_FAILURES"; fi
  printf 'skill fingerprint: %s (%s skills)\n' "$(skill_fingerprint)" \
    "$(find "$SKILL_SET" -mindepth 1 -maxdepth 1 -type d | wc -l)"
}

# --- The runtime matrix: manifest.toml [matrix] and [outside] ---------------
# A provided cell must have a probe here, and the probe must pass. Missing and
# unsupported cells are shown as declared; S7 closes the missing ones.

in_store() { case "$(readlink -f "$1" 2>/dev/null)" in "$STORE_PREFIX"/*) return 0 ;; esac; return 1; }

# The skill root whose path ends in $1 (/.claude/skills or /.agents/skills).
skill_root() {
  local root roots
  IFS=: read -r -a roots <<< "$SKILL_ROOTS"
  for root in "${roots[@]}"; do case "$root" in *"$1") printf '%s\n' "$root"; return 0 ;; esac; done
  return 1
}

# probe <surface> <program>: 0 installed, 1 not installed, 2 no probe exists.
probe() {
  local path link found=0
  case "$1/$2" in
    rules/claude) in_store "$CLAUDE_INSTRUCTIONS" ;;
    rules/codex) head -n 1 "$CODEX_INSTRUCTIONS" 2>/dev/null | rg -qF 'GENERATED by codex-agents-render' ;;
    rules/pi) in_store "$PI_INSTRUCTIONS" ;;
    skills/claude) path=$(skill_root /.claude/skills) && [ "$(readlink -f "$path")" = "$SKILL_SET" ] ;;
    skills/codex) path=$(skill_root /.agents/skills) && [ "$(readlink -f "$path")" = "$SKILL_SET" ] ;;
    skills/pi)
      path=$(jq -r '.skills[0] // empty' "$PI_SETTINGS" 2>/dev/null) || return 1
      [ -n "$path" ] && [ "$(readlink -f "${path/#\~/$HOME}")" = "$SKILL_SET" ] ;;
    guards/claude) jq -e '[.. | .command? // empty | select(contains("/etc/agent-harness/guards/"))] | length > 0' "$CLAUDE_SETTINGS" >/dev/null 2>&1 ;;
    guards/codex) in_store "$CODEX_HOOKS" && rg -qF 'hook-bridge.py' "$CODEX_HOOKS" ;;
    guards/pi) in_store "$PI_HOOK_BRIDGE" ;;
    mcp/claude) in_store "$CLAUDE_MCP" ;;
    mcp/codex) command -v codex-mcp-sync >/dev/null && codex-mcp-sync --check >/dev/null 2>&1 ;;
    commands/claude) in_store "$CLAUDE_HOME/commands" ;;
    commands/codex) in_store "$HOME/.codex/prompts" ;;
    commands/pi) in_store "$HOME/.pi/agent/prompts" ;;
    subagents/claude) in_store "$CLAUDE_HOME/agents" ;;
    memory/claude)
      for link in "$CLAUDE_HOME"/projects/*/memory; do
        [ -e "$link" ] || [ -L "$link" ] || continue
        found=1
        case "$(readlink -f "$link")" in "$STATE"/projects/*) ;; *) return 1 ;; esac
      done
      [ "$found" = 1 ] ;;
    # Codex and Pi read the same store: memory-recall, run by the installed
    # bridge (Codex table) or from the settings.json registry (Pi).
    memory/codex) rg -qF '"memory-recall"' "$HARNESS_ROOT/adapters/codex/hook-bridge.py" && probe memory claude ;;
    memory/pi) rg -qF 'guards/memory-recall.sh' "$HARNESS_ROOT/adapters/claude/settings.json" && probe memory claude ;;
    *) return 2 ;;
  esac
}

# Print surface by program for this host; return the number of bad cells.
matrix_table() {
  local surface program declared rc mark bad=0 programs
  [ -r "$MATRIX" ] || { printf 'matrix: manifest matrix not configured\n'; return 1; }
  programs=$(jq -r '[.matrix[] | keys[]] | unique | .[]' "$MATRIX")
  printf '%-10s' "$(hostname)"
  for program in $programs; do printf ' %-12s' "$program"; done
  printf '\n'
  for surface in $(jq -r '.matrix | keys[]' "$MATRIX"); do
    printf '%-10s' "$surface"
    for program in $programs; do
      declared=$(jq -r --arg s "$surface" --arg p "$program" '.matrix[$s][$p] // "undeclared"' "$MATRIX")
      mark=$declared
      case "$declared" in
        provided)
          rc=0; probe "$surface" "$program" || rc=$?
          case "$rc" in 0) ;; 2) mark='NO-PROBE'; bad=$((bad + 1)) ;; *) mark='NOT-FOUND'; bad=$((bad + 1)) ;; esac ;;
        missing|unsupported) ;;
        *) mark='UNDECLARED'; bad=$((bad + 1)) ;;
      esac
      printf ' %-12s' "$mark"
    done
    printf '\n'
  done
  return "$bad"
}

matrix_fleet() {
  local host bad=0
  validate_fleet
  for host in "${FLEET_HOSTS[@]}"; do
    if [ "$host" = "$(hostname)" ]; then
      matrix_table || bad=$((bad + 1))
    else
      ssh -o BatchMode=yes -o ConnectTimeout=8 "$host" 'agent-harness matrix' || bad=$((bad + 1))
    fi
    printf '\n'
  done
  [ "$bad" -eq 0 ]
}

# Skills a program loads from outside the harness must be listed in [outside].
check_outside_skills() {
  local name settings unlisted=()
  [ -r "$MATRIX" ] || { fail 'outside skills: manifest matrix not configured'; return; }
  for name in "$CODEX_SKILLS"/.system/*/; do
    [ -d "$name" ] || continue
    name=$(basename "$name")
    jq -e --arg n "$name" '.outside.codex.system // [] | index($n)' "$MATRIX" >/dev/null || unlisted+=("Codex system skill $name")
  done
  for settings in "$CLAUDE_SETTINGS" "$CLAUDE_HOME/settings.json"; do
    [ -r "$settings" ] || continue
    while IFS= read -r name; do
      jq -e --arg n "$name" '.outside.claude.plugins // [] | index($n)' "$MATRIX" >/dev/null || unlisted+=("Claude plugin $name")
    done < <(jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' "$settings" 2>/dev/null)
  done
  # claude.ai sync writes <bucket>/<plugin>/ plus <plugin>~gN/ generations.
  for name in "$CLAUDE_HOME"/plugins/synced/*/*/; do
    [ -d "$name" ] || continue
    name=$(basename "$name")
    case "$name" in *'~'*) continue ;; esac
    jq -e --arg n "$name" '.outside.claude.synced // [] | index($n)' "$MATRIX" >/dev/null || unlisted+=("claude.ai synced plugin $name")
  done
  if [ "${#unlisted[@]}" -eq 0 ]; then
    ok 'outside skills: every source is listed in the manifest'
  else
    for name in "${unlisted[@]}"; do fail "outside skills: $name is not listed in manifest.toml [outside]"; done
  fi
}

doctor_local() {
  failures=0
  check_skills
  check_outside_skills
  if matrix_table >/dev/null; then ok 'matrix: every provided cell is installed'; else fail 'matrix: a provided cell is not installed; run agent-harness matrix'; fi
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
  if systemctl --user --quiet is-active tracker-relay.service; then ok 'tracker-relay active'; else fail 'tracker-relay inactive: tracker pings to this host wait'; fi
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

# Bring the working copy level with github/main: fast-forward when behind,
# replay committed local work on top when diverged (publish ships committed
# work anyway). Before 2026-11-13 a diverged copy stopped every publish while
# another session's commit waited to be pushed. A conflict, or a rebase or
# merge another session has in progress, still stops.
sync_source() {
  local git_dir
  git_dir=$(git -C "$SOURCE" rev-parse --absolute-git-dir)
  if [ -e "$git_dir/rebase-merge" ] || [ -e "$git_dir/rebase-apply" ] || [ -e "$git_dir/MERGE_HEAD" ]; then
    printf 'agent-harness: static policy has a rebase or merge in progress; publish again after it ends\n' >&2
    return 1
  fi
  require_clean_tracked "$SOURCE" 'static policy' || return 1
  git -C "$SOURCE" fetch github refs/heads/main:refs/remotes/github/main
  if git -C "$SOURCE" merge-base --is-ancestor HEAD github/main; then
    git -C "$SOURCE" merge --ff-only --quiet github/main
  elif ! git -C "$SOURCE" merge-base --is-ancestor github/main HEAD; then
    git -C "$SOURCE" rebase --quiet github/main || {
      git -C "$SOURCE" rebase --abort
      printf 'agent-harness: local commits conflict with github/main; resolve in %s\n' "$SOURCE" >&2
      return 1
    }
  fi
}

publish_preflight() {
  validate_fleet
  require_clean_tracked "$SOURCE" 'static policy'
  require_clean_tracked "$NIXOS" 'nixos-hwc'
  [ "$(git -C "$SOURCE" branch --show-current)" = main ] || { printf 'agent-harness: static policy must be on main\n' >&2; return 1; }
  [ "$(git -C "$NIXOS" branch --show-current)" = main ] || { printf 'agent-harness: nixos-hwc must be on main\n' >&2; return 1; }

  # Other sessions share this working copy: they push to github, and they
  # commit here and push later. Both happen while the suites run (eight
  # minutes). Each attempt syncs to the newest main, runs the suites, and
  # ends when the checked revision and github/main are in line: github holds
  # it (publish it, no push) or it extends github (push it). A push that
  # lands between check and push sends the run round again.
  local attempt
  for attempt in 1 2 3; do
    sync_source || return 1
    (cd "$SOURCE" && checks/harness-policy-check)
    # The live tier too: suites that need GitHub, ~/.nixos sources and this
    # host's transcripts, which neither the commit gate nor the build check sees.
    (cd "$SOURCE" && bash guards/tests/run.sh --live)
    git -C "$SOURCE" fetch github refs/heads/main:refs/remotes/github/main
    if git -C "$SOURCE" merge-base --is-ancestor github/main HEAD \
        || git -C "$SOURCE" merge-base --is-ancestor HEAD github/main; then
      break
    fi
    [ "$attempt" -lt 3 ] || {
      printf 'agent-harness: github/main moved during each of 3 checked attempts; publish again when it is quiet\n' >&2
      return 1
    }
  done

  # nixos-hwc main moves only through the release runner. Being behind origin
  # is fine (the runner fast-forwards to the candidate); local commits not on
  # origin are another session's unpushed work, and the runner would refuse.
  nixos_main_in_origin || return 1
  static_revision=$(git -C "$SOURCE" rev-parse HEAD)
  locked=$(origin_pin)
  if [ "$locked" = "$static_revision" ]; then
    ok "nixos-hwc origin/main already pins static revision $static_revision"
  else
    ok "nixos-hwc will update static revision $locked -> $static_revision"
  fi
}

release_runner() {
  python3 "$NIXOS/workspace/nixos-dev/verification/release.py" --repo "$NIXOS" "$@"
}

nixos_main_in_origin() {
  git -C "$NIXOS" fetch --quiet origin refs/heads/main:refs/remotes/origin/main
  git -C "$NIXOS" merge-base --is-ancestor main origin/main || {
    printf 'agent-harness: nixos-hwc main has commits not on origin/main; push them (or let their session push), then publish again\n' >&2
    return 1
  }
}

origin_pin() { git -C "$NIXOS" show origin/main:flake.lock | jq -r '.nodes."agent-harness".locked.rev'; }

# The harness revision a host runs, or "unreachable".
host_revision() {
  if [ "$1" = "$(hostname)" ]; then expected_revision; return; fi
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$1" 'agent-harness revision' 2>/dev/null || printf 'unreachable\n'
}

# Hosts publish activates: this host always (the pin is integrated here), and
# the named ones. Before 2026-11-13 every publish switched the whole fleet.
publish_targets() {
  local host requested=() all=0
  validate_fleet
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --fleet) all=1 ;;
      --host) [ -n "${2:-}" ] || usage; requested+=("$2"); shift ;;
      *) usage ;;
    esac
    shift
  done
  TARGETS=("$(hostname)")
  [ "$all" = 0 ] || requested=("${FLEET_HOSTS[@]}")
  for host in "${requested[@]}"; do
    case " ${FLEET_HOSTS[*]} " in *" $host "*) ;; *) printf 'agent-harness: %s is not in the fleet (%s)\n' "$host" "${FLEET_HOSTS[*]}" >&2; return 1 ;; esac
    case " ${TARGETS[*]} " in *" $host "*) ;; *) TARGETS+=("$host") ;; esac
  done
}

# What publish does to each fleet host. Every activation goes through
# workspace/nixos-dev/verification/release.py on the host it activates.
print_plan() {
  local revision=$1 host current
  printf 'publish plan: harness %s (origin/main pins %s)\n' "$revision" "$locked"
  if [ "$locked" = "$revision" ]; then
    printf '  nixos-hwc: pin unchanged; no commit\n'
  else
    printf '  nixos-hwc: commit the pin on a branch from origin/main, release.py verify it, push it to origin main (fast-forward only)\n'
  fi
  for host in "${FLEET_HOSTS[@]}"; do
    current=$(host_revision "$host")
    if [ "$current" = "$revision" ]; then
      printf '  %s: already runs %s; no activation\n' "$host" "$revision"
    elif [ "$host" = "$(hostname)" ]; then
      printf '  %s (this host, runs %s): release.py deploy --candidate <pin commit>: verify, fast-forward main, switch\n' "$host" "$current"
    elif case " ${TARGETS[*]} " in *" $host "*) true ;; *) false ;; esac; then
      printf '  %s (runs %s): over ssh, pull its harness checkout --ff-only, then release.py deploy --candidate origin/main there\n' "$host" "$current"
    else
      printf '  %s (runs %s): not activated; add --host %s or --fleet\n' "$host" "$current" "$host"
    fi
  done
}

# Read-only: fetches remote refs, reports what a publish would do.
publish_plan() {
  local head
  git -C "$SOURCE" fetch --quiet github refs/heads/main:refs/remotes/github/main || warn 'could not fetch the harness github remote'
  git -C "$NIXOS" fetch --quiet origin refs/heads/main:refs/remotes/origin/main || warn 'could not fetch nixos-hwc origin'
  head=$(git -C "$SOURCE" rev-parse HEAD)
  locked=$(origin_pin)
  [ -z "$(git -C "$SOURCE" status --porcelain --untracked-files=no)" ] || warn "harness checkout has tracked changes; publish would refuse"
  [ -z "$(git -C "$NIXOS" status --porcelain)" ] || warn 'nixos-hwc checkout is not clean; publish would refuse'
  git -C "$NIXOS" merge-base --is-ancestor main origin/main || warn 'nixos-hwc main has commits not on origin/main; publish would refuse'
  git -C "$SOURCE" merge-base --is-ancestor github/main HEAD || warn "harness HEAD is not on top of github/main; publish first syncs onto it, so the revision will differ"
  print_plan "$head"
}

# Commit the pin on a branch from origin/main, verify it with the runner, and
# push it to origin main. A push that loses a race to another session starts
# again from the new origin/main; nothing reached main unverified.
integrate_pin() {
  local attempt worktree branch
  for attempt in 1 2 3; do
    nixos_main_in_origin || return 1
    if [ "$(origin_pin)" = "$static_revision" ]; then
      candidate=$(git -C "$NIXOS" rev-parse origin/main)
      ok "origin/main $candidate already pins $static_revision"
      return 0
    fi
    mkdir -p "$NIXOS-worktrees"
    worktree=$(mktemp -d "$NIXOS-worktrees/harness-publish.XXXXXX")
    branch="harness-publish/${worktree##*.}"
    git -C "$NIXOS" worktree add --quiet -b "$branch" "$worktree" origin/main
    (cd "$worktree" && nix flake update agent-harness)
    [ "$(jq -r '.nodes."agent-harness".locked.rev' "$worktree/flake.lock")" = "$static_revision" ] || {
      printf 'agent-harness: flake lock did not resolve static revision %s (left at %s)\n' "$static_revision" "$worktree" >&2
      return 1
    }
    git -C "$worktree" add flake.lock
    git -C "$worktree" commit --quiet -m "chore: publish agent harness $static_revision"
    candidate=$(git -C "$worktree" rev-parse HEAD)
    release_runner verify --candidate "$candidate" || {
      printf 'agent-harness: release verification refused pin commit %s; left at %s (branch %s)\n' "$candidate" "$worktree" "$branch" >&2
      return 1
    }
    if git -C "$NIXOS" push origin "$candidate:refs/heads/main"; then
      git -C "$NIXOS" worktree remove "$worktree"
      git -C "$NIXOS" branch --quiet -D "$branch"
      return 0
    fi
    git -C "$NIXOS" worktree remove --force "$worktree"
    git -C "$NIXOS" branch --quiet -D "$branch"
    warn "origin/main moved before the pin push (attempt $attempt); rebuilding the candidate"
  done
  printf 'agent-harness: origin/main moved during each of 3 attempts; publish again when it is quiet\n' >&2
  return 1
}

publish() {
  local mode=run
  case "${1:-}" in
    --plan|--check) mode=${1#--}; shift ;;
  esac
  publish_targets "$@"
  if [ "$mode" = plan ]; then publish_plan; return; fi
  publish_preflight
  print_plan "$static_revision"
  [ "$mode" != check ] || return 0

  # Remote authoring checkouts track the server mirror, while Nix pins GitHub.
  # Publish both before switching, so the checkout and active policy agree.
  # A remote already holding the checked revision (a newer push won) is skipped.
  local remote
  for remote in github origin; do
    git -C "$SOURCE" fetch --quiet "$remote" "refs/heads/main:refs/remotes/$remote/main" 2>/dev/null \
      && git -C "$SOURCE" merge-base --is-ancestor HEAD "$remote/main" \
      || git -C "$SOURCE" push "$remote" HEAD:main
  done
  static_revision=$(git -C "$SOURCE" rev-parse HEAD)

  local candidate host skipped=() untargeted=()
  integrate_pin || return 1

  # Every activation is the release runner on the host it activates: it
  # verifies the exact candidate, fast-forwards that host's main and switches.
  if [ "$(expected_revision)" = "$static_revision" ]; then
    ok "$(hostname) already runs $static_revision"
  elif ! release_runner deploy --candidate "$candidate"; then
    printf 'agent-harness: %s is on origin/main, but this host refused or failed activation; fix that, then: python3 workspace/nixos-dev/verification/release.py deploy --candidate origin/main\n' "$candidate" >&2
    return 1
  fi

  # A remote host runs its own runner against origin/main, which now holds the
  # pin. Its gate refuses a checkout with another session's unpushed commits;
  # that host is reported and the rest continue (before 2026-11-12 the first
  # such host stopped the loop).
  for host in "${TARGETS[@]}"; do
    [ "$host" != "$(hostname)" ] || continue
    case "$(host_revision "$host")" in
      unreachable) skipped+=("$host (unreachable)") ;;
      "$static_revision") ok "$host already runs $static_revision" ;;
      *) ssh -t "$host" "git -C ~/800_agents/harness pull --ff-only && cd ~/.nixos && git fetch --quiet origin && python3 workspace/nixos-dev/verification/release.py deploy --candidate origin/main" \
           || skipped+=("$host (refused or failed; see above)") ;;
    esac
  done
  for host in "${FLEET_HOSTS[@]}"; do
    case " ${TARGETS[*]} " in *" $host "*) ;; *) untargeted+=("$host") ;; esac
  done
  if [ "${#skipped[@]}" -gt 0 ]; then
    printf 'agent-harness: not switched: %s. Fix that host, then publish again with --host.\n' "${skipped[*]}" >&2
  fi
  # The CLI now on PATH, not "$0": this process is the pre-switch store copy,
  # whose expected manifest still names the old revision, so re-running it
  # reported every freshly switched host as a mismatch (2026-09-30).
  if [ "${#untargeted[@]}" -eq 0 ]; then
    agent-harness doctor --fleet
  else
    agent-harness doctor
    printf 'not activated (not requested): %s. They keep their current harness; activate with: agent-harness publish --host <name>\n' "${untargeted[*]}"
  fi
  [ "${#skipped[@]}" -eq 0 ]
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
  printf 'usage: agent-harness [status|doctor [--fleet]|matrix [--fleet]|drift|revision|sync|validate-state|diff|publish [--plan|--check] [--host <name>]... [--fleet]]\n' >&2
  exit 2
}

command=${1:-}
if [ -z "$command" ] && [ -t 0 ]; then
  printf '1 status\n2 doctor\n3 fleet doctor\n4 sync\n5 validate state\n6 static diff\n7 publish plan\n8 publish (this host)\n> '
  read -r choice
  case "$choice" in
    1) command=status ;; 2) command=doctor ;; 3) command=doctor; set -- doctor --fleet ;;
    4) command=sync ;; 5) command=validate-state ;; 6) command="diff" ;; 7) command=publish; set -- publish --plan ;;
    8) command=publish ;; *) exit 2 ;;
  esac
fi

case "$command" in
  status)
    systemctl --user show agent-state-sync.timer -p ActiveState -p SubState -p LastTriggerUSec --no-pager
    show_state_case
    git -C "$STATE" status --short --branch
    ;;
  doctor) if [ "${2:-}" = --fleet ]; then doctor_fleet; else doctor_local; fi ;;
  matrix) if [ "${2:-}" = --fleet ]; then matrix_fleet; else matrix_table; fi ;;
  drift) drift ;;
  revision) expected_revision ;;
  sync) exec agent-state-sync sync ;;
  validate-state) exec agent-state-validate ;;
  diff) git --no-pager diff --no-index /etc/agent-harness "$SOURCE" || [ "$?" = 1 ] ;;
  publish) publish "${@:2}" ;;
  *) usage ;;
esac
