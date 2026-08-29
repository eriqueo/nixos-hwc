# claude-settings-heal.jq — converge the gate-hook wiring into ~/.claude/settings.json.
#
# ONE PRODUCER. index.nix reads this file with builtins.readFile, and
# settings-heal.test.sh runs the same bytes against fixtures. A filter that lived
# only inside the Nix string could not be tested without rebuilding, and a copy in
# the test would be a second producer of the same logic.
#
# WHY EXACT-MATCH-AFTER-NORMALISE AND NOT `contains`.
# The previous test asked "does any command contain this substring?" Two defects
# followed from that one question, both measured 2026-08-25 (harness-live-state.md
# D1/D2):
#
#   1. A fragment carrying an ARGUMENT never matched its own wrapped form. The
#      wrapped command reads `… standing-instructions.sh' inject`, with a closing
#      quote between the filename and the argument, so the substring
#      "standing-instructions.sh inject" does not occur. `ensure` appended on every
#      activation, and settings.json ended up injecting standing instructions twice
#      per turn.
#   2. A fragment naming only the PATH cannot separate two entries that run the
#      same script with different arguments. Measured: a path-only test reports
#      `sync` present when only `inject` is wired, so `sync` would never be added.
#
# The canonical command is not written twice. It is derived from the entry itself
# ($entry.hooks[0].command | norm), so the wiring JSON in index.nix stays the single
# source of the command text, and this filter stays correct whether that text is
# emitted bare or inside the `bash -n` wrapper.
#
# WHAT norm DELIBERATELY DOES NOT DO. It does not reorder redirections. A hand-edited
# entry that moves `2>/dev/null` to a different position is a different command, and
# treating it as equal would let a real divergence pass unnoticed. See the
# `unmatched-by-design` cases in settings-heal.test.sh.

# Strip the safety wrapper and quoting so a live command collapses to `bash <path> [args]`.
def norm:
    gsub("^bash +-n +[^&]*&& +"; "")
  | gsub(" *\\|\\| +exit +0 *;? *$"; "")
  | gsub("[\"']"; "")
  | gsub("[[:space:]]+"; " ")
  | sub("^ +"; "")
  | sub(" +$"; "");

def has_cmd($ev; $canon):
  [.hooks[$ev][]?.hooks[]?.command // empty] | map(norm == $canon) | any;

# ensure($ev; $entry; $on) — append $entry under $ev when $on is true and no live
# command normalises to the same canonical form. Never edits and never removes: the
# runtime keys Claude Code writes to this file must survive.
#
# $on is the per-hook enable flag from index.nix. It is what makes a hook
# DISARMABLE. Before it existed, removing an entry from settings.json guaranteed the
# next activation re-appended it, so the arming decision could not be expressed
# anywhere durable. Setting the flag false does NOT delete a live entry; it stops
# this filter restoring one. Deleting the entry is a separate, deliberate act.
def ensure($ev; $entry; $on):
  if ($on | not) then .
  else
    ($entry.hooks[0].command | norm) as $canon
    | if has_cmd($ev; $canon)
      then .
      else .hooks[$ev] = ((.hooks[$ev] // []) + [$entry])
      end
  end;

$wire[0] as $w
| $enable[0] as $en
| ensure("PreToolUse";      $w.enforceTools;      $en.enforceTools)
| ensure("PreToolUse";      $w.premortemGate;     $en.premortemGate)
| ensure("PreToolUse";      $w.claimcheckArtifact; $en.claimcheckArtifact)
| ensure("PostToolUse";     $w.trackEvidence;     $en.trackEvidence)
| ensure("UserPromptSubmit"; $w.turnStamp;        $en.turnStamp)
| ensure("Stop";            $w.claimGuard;        $en.claimGuard)
| ensure("PreToolUse";      $w.nixosPrimer;       $en.nixosPrimer)
| ensure("PreToolUse";      $w.pathConventions;   $en.pathConventions)
| ensure("PreToolUse";      $w.charterGate;       $en.charterGate)
| ensure("UserPromptSubmit"; $w.standingInject;   $en.standingInject)
| ensure("UserPromptSubmit"; $w.standingSync;     $en.standingSync)
| ensure("Stop";            $w.ste100Guard;       $en.ste100Guard)
| ensure("SubagentStop";    $w.ste100Guard;       $en.ste100Guard)
| ensure("SessionStart";    $w.memoryStaleness;   $en.memoryStaleness)
| .env.SLASH_COMMAND_TOOL_CHAR_BUDGET = (.env.SLASH_COMMAND_TOOL_CHAR_BUDGET // "30000")
