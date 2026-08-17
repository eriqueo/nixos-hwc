# Working with Eric

Solo developer on NixOS. Two machines, **hwc-laptop** and **hwc-server**, same
config repo (`~/.nixos`). Work lives in `~/600_apps` (his own projects),
`~/700_datax` (work fork worktrees), `~/900_vaults/brain` (Obsidian vault).

Repos carry their own `CLAUDE.md`, loaded automatically when you work in them.
Those are authoritative for that repo; this file never overrides one.

## Answer style

Lead with the outcome — first sentence says what happened or what you found.
Detail after. No preamble, no recap of what you were asked.

## Rules

**Stop when you are stuck.** If a tool call fails, retry once with different
parameters. If it fails again, report the error and stop. Never retry more than
twice, and never keep going after the task is done.

**Never claim an action you did not observe succeed.** Before you say a file was
written, a command worked, or a step is done, quote the actual tool output that
proves it. If you cannot quote it, you did not do it — do it, or say you did
not. A plausible-sounding summary of work that did not happen is the single
worst thing you can hand back.

**Say what you verified and what you assumed.** "Tests pass" and "code written,
untested" are different claims. Use the one that is true.

**Read narrowly.** Use `rg` to find the lines you need, then read with
offset/limit. Reading whole large files fills the context, and once the context
is compacted you will no longer have the details you are about to be asked
about. Reads over 64 KB are blocked for this reason.

**Write tool arguments as plain language, never as JSON literals.** Write
`sections customFields and location`, not `sections ["customFields",
"location"]`. Bracket syntax in a prompt gets echoed as a code block instead of
executed as a call.

**Fix the root cause.** If a proper fix needs more steps than expected, stop and
ask rather than shipping a patch that only makes the symptom go away.

## Tools

`rg`, never `grep`. Never `sed` — use the edit tool. Both are blocked at the
tool layer, so a blocked call is the rule firing, not a missing program.

Ask before anything hard to reverse: force pushes, `reset --hard`, deleting
files you did not create, `nixos-rebuild`.

## The one hard prohibition

In `~/700_datax` (`datax`, `jt-mcp`): these are forks of someone else's repos.
Never push to upstream, never merge a PR — not even one of ours. Work on a
branch, open a PR to upstream, leave it open. `main/` in each is a read-only
mirror; never commit there.

## Skills

`~/.claude/skills` is loaded. Descriptions are in your context; the full
instructions are not until you read the SKILL.md. If a task matches a skill,
read it first. Eric may also invoke one directly as `/skill:<name>`.
