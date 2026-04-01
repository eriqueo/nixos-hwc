#!/usr/bin/env bash
# PreToolUse hook for nixos-hwc
# Exit 0 + JSON deny/ask = block or gate the tool call
# Exit 0 + no output = allow silently

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty' 2>/dev/null)

deny() {
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"$1\"}}"
  exit 0
}

ask() {
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"$1\"}}"
  exit 0
}

# ── Bash tool checks ──
if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null)
  [ -z "$COMMAND" ] && exit 0

  # Block grep
  echo "$COMMAND" | rg -q '^\s*(grep|command grep|/usr/bin/grep)\b' && \
    deny "Use rg instead of grep."

  # Block sed
  echo "$COMMAND" | rg -q '^\s*(sed|command sed|/usr/bin/sed)\b' && \
    deny "Use the Edit tool instead of sed."

  # Gate nixos-rebuild
  echo "$COMMAND" | rg -q 'nixos-rebuild' && \
    ask "nixos-rebuild detected — did you run hostname to confirm the target machine?"

  # Gate git push --force
  echo "$COMMAND" | rg -q 'git\s+push\s+.*--force' && \
    ask "Force push detected — this can destroy remote history. Are you sure?"

  # Gate destructive git operations
  echo "$COMMAND" | rg -q 'git\s+(reset\s+--hard|clean\s+-f)' && \
    ask "Destructive git operation — this discards uncommitted work. Are you sure?"

  exit 0
fi

# ── Edit/Write tool checks on secrets files ──
if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
  FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
  [ -z "$FILE_PATH" ] && exit 0

  # Remind about secrets conventions when editing secret declarations
  echo "$FILE_PATH" | rg -q 'domains/secrets/' && \
    ask "Editing secrets domain — remember: group = \\\"secrets\\\"; mode = \\\"0440\\\" always."

  # Warn about port conflicts when editing routes
  echo "$FILE_PATH" | rg -q 'domains/networking/routes\.nix' && \
    ask "Editing Caddy routes — check for port conflicts. Used ports: 1443-18095 range. See existing assignments before adding new ones."
fi

exit 0
