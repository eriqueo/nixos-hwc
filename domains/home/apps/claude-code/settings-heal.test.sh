#!/usr/bin/env bash
# settings-heal.test.sh — fixture test for settings-heal.jq.
#
# WHY THIS EXISTS AND WHY ITS FIXTURES ARE HAND-WRITTEN.
# The obvious way to test the heal is to run it against ~/.claude/settings.json and
# ~/.claude/settings.json.pre-heal.bak. Both of those files were WRITTEN BY THE HEAL.
# A test whose only inputs come from the thing under test cannot detect drift — that
# is this repo's `vacuous-check` family, and MISTAKES.md:70 is the standing example:
# two selftest cases that pass against a guard which does not contain the mechanism
# they claim to pin.
#
# So every fixture below is typed by hand in a shape the heal does not emit:
# double quotes, an added redirect, a moved 2>/dev/null, extra whitespace, a
# trailing semicolon. The `unmatched-by-design` block records the variants the
# normaliser deliberately does NOT collapse, so a future reader can tell a limit
# from a bug.
#
# Run: bash settings-heal.test.sh
# Exit: 0 all pass · 1 a case failed
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQF="$HERE/settings-heal.jq"
[ -f "$JQF" ] || { echo "FATAL: $JQF not found"; exit 1; }

PASS=0; FAIL=0
CANON="bash /home/eric/.claude-config/hooks/claim-guard.sh"

# The wiring entry the module would append, in its WRAPPED emitted form.
WIRE=$(jq -n --arg c "bash -n '/home/eric/.claude-config/hooks/claim-guard.sh' 2>/dev/null && bash '/home/eric/.claude-config/hooks/claim-guard.sh' || exit 0" '
{ claimGuard: { matcher: "*", hooks: [ { type: "command", command: $c, timeout: 15, statusMessage: "Claim guard" } ] } }')

# Every other key the filter references must exist, or jq errors on a null entry.
FULLWIRE=$(jq -n --argjson w "$WIRE" '
  $w + ( [ "enforceTools","premortemGate","trackEvidence","turnStamp","nixosPrimer",
           "pathConventions","charterGate","standingInject","standingSync",
           "ste100Guard","memoryStaleness" ]
        | map({ key: ., value: { matcher: "*", hooks: [ { type: "command", command: ("bash /nonexistent/" + . + ".sh") } ] } })
        | from_entries )')

# Only claimGuard is enabled, so each case tests exactly one ensure() call.
ONLY_CLAIM=$(jq -n '
  { claimGuard: true }
  + ( [ "enforceTools","premortemGate","trackEvidence","turnStamp","nixosPrimer",
        "pathConventions","charterGate","standingInject","standingSync",
        "ste100Guard","memoryStaleness" ] | map({key:., value:false}) | from_entries )')

# run_case <name> <expect: match|append> <live command string>
run_case() {
  local name="$1" expect="$2" cmd="$3" before after got
  local input; input=$(jq -n --arg c "$cmd" '{hooks:{Stop:[{matcher:"*",hooks:[{type:"command",command:$c}]}]}}')
  before=$(jq '[.hooks.Stop[].hooks[]] | length' <<<"$input")
  after=$(jq --argjson wire "[$FULLWIRE]" --argjson enable "[$ONLY_CLAIM]" \
            --args -f "$JQF" <<<"$input" 2>/dev/null \
          | jq '[.hooks.Stop[].hooks[]] | length' 2>/dev/null)
  [ -z "$after" ] && { printf '  FAIL %-42s jq error\n' "$name"; FAIL=$((FAIL+1)); return; }
  if [ "$after" -eq "$before" ]; then got=match; else got=append; fi
  if [ "$got" = "$expect" ]; then
    printf '  ok   %-42s %s\n' "$name" "$got"; PASS=$((PASS+1))
  else
    printf '  FAIL %-42s expected %s, got %s\n' "$name" "$expect" "$got"; FAIL=$((FAIL+1))
  fi
}

echo "== normaliser: forms that MUST be recognised as already present =="
run_case "bare canonical"                match "bash /home/eric/.claude-config/hooks/claim-guard.sh"
run_case "wrapped, as the heal emits it" match "bash -n '/home/eric/.claude-config/hooks/claim-guard.sh' 2>/dev/null && bash '/home/eric/.claude-config/hooks/claim-guard.sh' || exit 0"
run_case "hand-edit: double quotes"      match "bash -n \"/home/eric/.claude-config/hooks/claim-guard.sh\" 2>/dev/null && bash \"/home/eric/.claude-config/hooks/claim-guard.sh\" || exit 0"
run_case "hand-edit: extra whitespace"   match "bash  -n   '/home/eric/.claude-config/hooks/claim-guard.sh'  2>/dev/null  &&  bash   '/home/eric/.claude-config/hooks/claim-guard.sh'   ||  exit 0"
run_case "hand-edit: trailing semicolon" match "bash -n '/home/eric/.claude-config/hooks/claim-guard.sh' 2>/dev/null && bash '/home/eric/.claude-config/hooks/claim-guard.sh' || exit 0;"
run_case "hand-edit: no quotes at all"   match "bash -n /home/eric/.claude-config/hooks/claim-guard.sh 2>/dev/null && bash /home/eric/.claude-config/hooks/claim-guard.sh || exit 0"

echo "== forms that MUST be treated as absent =="
run_case "a different hook entirely"     append "bash /home/eric/.claude-config/hooks/followup-guard.sh"
run_case "same script, an argument added" append "bash /home/eric/.claude-config/hooks/claim-guard.sh --strict"
run_case "empty event"                   append "bash /home/eric/.claude-config/hooks/other.sh"

echo "== unmatched-by-design: a real divergence must NOT be collapsed =="
run_case "added redirect changes the cmd" append "bash /home/eric/.claude-config/hooks/claim-guard.sh > /tmp/log"
run_case "2>/dev/null moved to the tail"  append "bash -n '/home/eric/.claude-config/hooks/claim-guard.sh' && bash '/home/eric/.claude-config/hooks/claim-guard.sh' 2>/dev/null || exit 0"

echo "== the disarm flag =="
DISARM=$(jq -n '[ "claimGuard","enforceTools","premortemGate","trackEvidence","turnStamp","nixosPrimer","pathConventions","charterGate","standingInject","standingSync","ste100Guard","memoryStaleness" ] | map({key:., value:false}) | from_entries')
n=$(jq -n '{hooks:{Stop:[]}}' \
    | jq --argjson wire "[$FULLWIRE]" --argjson enable "[$DISARM]" -f "$JQF" \
    | jq '[.hooks.Stop[]?.hooks[]?] | length')
if [ "$n" = "0" ]; then
  printf '  ok   %-42s disarmed hook is not appended\n' "all flags false"; PASS=$((PASS+1))
else
  printf '  FAIL %-42s expected 0 appended, got %s\n' "all flags false" "$n"; FAIL=$((FAIL+1))
fi
n=$(jq -n '{hooks:{Stop:[]}}' \
    | jq --argjson wire "[$FULLWIRE]" --argjson enable "[$ONLY_CLAIM]" -f "$JQF" \
    | jq '[.hooks.Stop[]?.hooks[]?] | length')
if [ "$n" = "1" ]; then
  printf '  ok   %-42s enabled hook is appended once\n' "claimGuard true"; PASS=$((PASS+1))
else
  printf '  FAIL %-42s expected 1 appended, got %s\n' "claimGuard true" "$n"; FAIL=$((FAIL+1))
fi

echo "== idempotence =="
once=$(jq -n '{hooks:{Stop:[]}}' | jq --argjson wire "[$FULLWIRE]" --argjson enable "[$ONLY_CLAIM]" -f "$JQF")
twice=$(jq --argjson wire "[$FULLWIRE]" --argjson enable "[$ONLY_CLAIM]" -f "$JQF" <<<"$once")
if [ "$(jq -S . <<<"$once")" = "$(jq -S . <<<"$twice")" ]; then
  printf '  ok   %-42s second run is a no-op\n' "run twice"; PASS=$((PASS+1))
else
  printf '  FAIL %-42s second run changed the file\n' "run twice"; FAIL=$((FAIL+1))
fi

echo
echo "settings-heal: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
