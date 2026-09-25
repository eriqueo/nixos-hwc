#!/usr/bin/env bash
set -Eeuo pipefail

STATE=${AGENT_STATE_DIR:-$HOME/.agent-state}
CONFIG_DIRS=${AGENT_CONFIG_DIRS:-$HOME/.claude:$HOME/.claude_dx2_home}
HOST=${AGENT_HOST:-$(uname -n)}
VALIDATOR=${AGENT_STATE_VALIDATOR:-$(realpath "$(dirname "$0")/state-validate.sh")}
NOTIFY_URL=${AGENT_STATE_NOTIFY_URL-}  # set by the agent-harness module; empty = no notify
CASE_FILE="$STATE/.git/.sync-case.json"
CURRENT_FINGERPRINT=""
CASE_TRANSITION=0
PREVIOUS_CASE_STATE=""

log() { printf 'agent-state: %s\n' "$*"; }
notify() {
  [ -n "$NOTIFY_URL" ] || return 1
  command -v curl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -n --arg title "$1" --arg body "$2" \
    '{topic:"monitoring",title:$title,body:$body,priority:2,source:"agent-state-sync"}' \
    | curl -fsS --max-time 5 -H 'content-type: application/json' -d @- \
        "$NOTIFY_URL" >/dev/null 2>&1
}
case_field() {
  [ -r "$CASE_FILE" ] || return 0
  jq -r "$1 // empty" "$CASE_FILE" 2>/dev/null || true
}

record_case() {
  local state=$1 outcome=$2 fingerprint=$3 previous_state previous_fingerprint tmp
  previous_state=$(case_field '.state')
  previous_fingerprint=$(case_field '.caseId')
  PREVIOUS_CASE_STATE=$previous_state
  CASE_TRANSITION=0
  if [ "$previous_state" != "$state" ] || [ "$previous_fingerprint" != "$fingerprint" ]; then
    CASE_TRANSITION=1
    log "case transition state=$previous_state->$state outcome=$outcome case=$fingerprint"
  fi
  if [ "$previous_state" = "$state" ] && [ "$previous_fingerprint" = "$fingerprint" ] \
      && [ "$(case_field '.lastOutcome')" = "$outcome" ]; then
    return 0
  fi
  tmp=$(mktemp "$STATE/.git/.sync-case.json.XXXXXX")
  jq -n \
    --arg caseId "$fingerprint" \
    --arg state "$state" \
    --arg outcome "$outcome" \
    --arg host "$HOST" \
    --arg at "$(date -Iseconds)" \
    '{schemaVersion:1,caseId:$caseId,state:$state,lastOutcome:$outcome,host:$host,updatedAt:$at}' \
    > "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$CASE_FILE"
}

notify_failure_transition() {
  [ "$CASE_TRANSITION" -eq 1 ] || return 0
  notify "Agent state sync blocked" \
    "State sync is blocked on $HOST ($1). Inspect journalctl --user -u agent-state-sync.service." || true
}

notify_recovery_transition() {
  [ "$CASE_TRANSITION" -eq 1 ] || return 0
  [ "$PREVIOUS_CASE_STATE" = blocked ] || return 0
  notify "Agent state sync recovered" "State sync is healthy again on $HOST." || true
}

state_fingerprint() {
  local path
  {
    printf 'validator\0'
    sha256sum "$VALIDATOR"
    printf 'head\0'
    git rev-parse HEAD
    printf 'schema\0'
    sha256sum .harness-schema.json
    printf 'status\0'
    git status --porcelain=v1 -z --untracked-files=all -- \
      MISTAKES.md .mistakes-dismissed.log .harness-schema.json projects
    {
      git diff --name-only -z HEAD -- MISTAKES.md .mistakes-dismissed.log .harness-schema.json projects
      git diff --cached --name-only -z -- MISTAKES.md .mistakes-dismissed.log .harness-schema.json projects
      git ls-files --others --exclude-standard -z -- MISTAKES.md .mistakes-dismissed.log .harness-schema.json projects
    } | sort -zu | while IFS= read -r -d '' path; do
      printf 'path=%s\0' "$path"
      if [ -f "$path" ]; then
        sha256sum "$path"
      elif [ -L "$path" ]; then
        printf 'symlink=%s\n' "$(readlink "$path")"
      else
        printf 'deleted\n'
      fi
    done
  } | sha256sum | awk '{print $1}'
}

on_error() {
  local status=$?
  trap - ERR
  if [ -n "$CURRENT_FINGERPRINT" ] && [ -d "$STATE/.git" ]; then
    record_case blocked sync-failed "$CURRENT_FINGERPRINT" || true
    notify_failure_transition sync-failed
  fi
  exit "$status"
}
trap on_error ERR

link_memories() {
  [ -d "$STATE/.git" ] || { log "missing git clone at $STATE"; return 1; }
  mkdir -p "$STATE/projects"
  local config project slug source target file conflict
  IFS=: read -r -a dirs <<< "$CONFIG_DIRS"

  for config in "${dirs[@]}"; do
    mkdir -p "$config/projects"
    for project in "$config"/projects/*; do
      [ -d "$project" ] || continue
      slug=${project##*/}
      [[ "$slug" == *-tmp-* ]] && continue
      source="$project/memory"
      target="$STATE/projects/$slug/memory"
      if [ -d "$source" ] && [ ! -L "$source" ]; then
        mkdir -p "$target"
        for file in "$source"/*; do
          [ -f "$file" ] || continue
          if [ -e "$target/${file##*/}" ] && ! cmp -s "$file" "$target/${file##*/}"; then
            conflict="$target/${file##*/}.from-$HOST.md"
            cp -p "$file" "$conflict"
            log "kept conflicting import as $conflict"
          else
            cp -p "$file" "$target/"
          fi
        done
        find "$source" -mindepth 1 -maxdepth 1 -type f -delete
        rmdir "$source" 2>/dev/null || true
      fi
      if [ -d "$target" ]; then
        if [ -L "$source" ] && [ "$(readlink "$source")" != "$target" ]; then
          unlink "$source"
        fi
        [ -e "$source" ] || ln -s "$target" "$source"
      fi
    done

    for target in "$STATE"/projects/*/memory; do
      [ -d "$target" ] || continue
      slug=${target#"$STATE/projects/"}; slug=${slug%/memory}
      [[ "$slug" == *-tmp-* ]] && continue
      mkdir -p "$config/projects/$slug"
      source="$config/projects/$slug/memory"
      if [ -L "$source" ] && [ "$(readlink "$source")" != "$target" ]; then
        unlink "$source"
      fi
      [ -e "$source" ] || ln -s "$target" "$source"
    done
  done
}

sync_state() {
  link_memories
  cd "$STATE"
  exec 9>.git/.sync.lock
  flock 9
  CURRENT_FINGERPRINT=$(state_fingerprint)
  if [ "$(case_field '.state')" = blocked ] \
      && [ "$(case_field '.lastOutcome')" = validation-failed ] \
      && [ "$(case_field '.caseId')" = "$CURRENT_FINGERPRINT" ]; then
    log "unchanged blocked case $CURRENT_FINGERPRINT; validation and network skipped"
    trap - ERR
    return 75
  fi

  validation_ok=0
  if AGENT_STATE_DIR="$STATE" "$VALIDATOR"; then validation_ok=1; fi
  after_validation=$(state_fingerprint)
  if [ "$after_validation" != "$CURRENT_FINGERPRINT" ]; then
    log 'state changed during validation; retrying once with the new case'
    CURRENT_FINGERPRINT=$after_validation
    validation_ok=0
    if AGENT_STATE_DIR="$STATE" "$VALIDATOR"; then validation_ok=1; fi
  fi
  if [ "$validation_ok" -ne 1 ]; then
    record_case blocked validation-failed "$CURRENT_FINGERPRINT"
    notify_failure_transition validation-failed
    trap - ERR
    return 1
  fi

  git add -A -- MISTAKES.md projects
  git add -A -- .harness-schema.json
  [ ! -e .mistakes-dismissed.log ] || git add -A -- .mistakes-dismissed.log
  if ! git diff --cached --quiet; then
    git commit -m "sync($HOST): agent state $(date -Iminutes)"
  fi
  git fetch origin
  if git rev-parse --verify '@{upstream}' >/dev/null 2>&1; then
    if ! git merge --no-edit '@{upstream}'; then
      unresolved=$(git diff --name-only --diff-filter=U)
      while IFS= read -r path; do
        [ -n "$path" ] || continue
        case "$path" in
          projects/*/memory/*.md)
            copy="${path%.md}.from-$HOST.md"
            git show ":3:$path" > "$copy"
            git checkout --ours -- "$path"
            git add -- "$path" "$copy"
            log "kept hub conflict as $copy"
            notify "Agent memory conflict" "$path kept with $copy on $HOST" || true
            ;;
          MISTAKES.md)
            git checkout --ours -- "$path"
            git show ":3:$path" >> "$path"
            git add -- "$path"
            ;;
          *)
            git merge --abort 2>/dev/null || true
            log "unsupported merge conflict: $path"
            return 1
            ;;
        esac
      done <<< "$unresolved"
      git commit --no-edit
    fi
  fi
  git push
  CURRENT_FINGERPRINT=$(state_fingerprint)
  record_case resolved synced "$CURRENT_FINGERPRINT"
  notify_recovery_transition
  rm -f .git/.sync-alert-state
}

case "${1:-sync}" in
  link) link_memories ;;
  sync) sync_state ;;
  *) echo "usage: agent-state-sync [link|sync]" >&2; exit 2 ;;
esac
