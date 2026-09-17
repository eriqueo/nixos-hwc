#!/usr/bin/env bash
set -euo pipefail

STATE=${AGENT_STATE_DIR:-$HOME/.agent-state}
CONFIG_DIRS=${AGENT_CONFIG_DIRS:-$HOME/.claude:$HOME/.claude_dx2_home}
HOST=${AGENT_HOST:-$(uname -n)}
VALIDATOR=${AGENT_STATE_VALIDATOR:-$(realpath "$(dirname "$0")/state-validate.sh")}

log() { printf 'agent-state: %s\n' "$*"; }
notify() {
  command -v curl >/dev/null 2>&1 || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -n --arg title "$1" --arg body "$2" \
    '{topic:"monitoring",title:$title,body:$body,priority:2,source:"agent-state-sync"}' \
    | curl -fsS --max-time 5 -H 'content-type: application/json' -d @- \
        http://127.0.0.1:11600/notify >/dev/null 2>&1 || true
}

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
  AGENT_STATE_DIR="$STATE" bash "$VALIDATOR"
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
            notify "Agent memory conflict" "$path kept with $copy on $HOST"
            ;;
          MISTAKES.md)
            git checkout --ours -- "$path"
            git show ":3:$path" >> "$path"
            git add -- "$path"
            ;;
          *)
            git merge --abort 2>/dev/null || true
            log "unsupported merge conflict: $path"
            notify "Agent state sync failed" "Unsupported conflict at $path on $HOST"
            return 1
            ;;
        esac
      done <<< "$unresolved"
      git commit --no-edit
    fi
  fi
  if ! git push; then
    notify "Agent state sync failed" "Push failed on $HOST. Inspect agent-state-sync.service."
    return 1
  fi
}

case "${1:-sync}" in
  link) link_memories ;;
  sync) sync_state ;;
  *) echo "usage: agent-state-sync [link|sync]" >&2; exit 2 ;;
esac
