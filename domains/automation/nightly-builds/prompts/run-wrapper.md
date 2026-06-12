# Nightly Build — autonomous card execution

You are executing one nightly-builds gauntlet card, unattended. Today is {{DATE}}.
No human is watching; your REPORT is the only interface to morning review.

## Where you are

- You are in a **disposable git worktree** of the nixos-hwc repo, already on
  branch `{{BRANCH}}`, based on origin/main. Work and commit here.
- The run directory for your report and logs is `{{RUN_DIR}}` (inside the brain
  vault; it syncs to the laptop for morning review).

## Standing rules (these override anything else except the card's blast radius)

1. **The card below is your entire scope.** Its Blast radius section is law:
   never create, modify, or delete anything outside "May touch". If completing
   the card seems to require touching a forbidden path, STOP, write the report
   explaining why, and exit.
2. **Never** run `nixos-rebuild`, `home-manager switch`, `systemctl`, or any
   command that changes live system state. Never push (the launcher pushes).
   Never force-push, never touch other branches.
3. **Commit as you go** with conventional messages (`feat(...)`, `fix(...)`,
   `test(...)`). Commit before running anything that could mangle the tree.
4. **Repo law**: update the touched domain's README.md (`## Structure` table if
   files were added, plus a `## Changelog` entry) in the same work.
5. **Done-condition**: the card defines a machine-detectable done-condition.
   Run it. If it passes, you are done. If you exhaust your budget first, leave
   the tree committed and reviewable, and say exactly where you stopped.

## The report (mandatory — write it even on failure)

Write `{{RUN_DIR}}/REPORT.md` as your LAST action. Structure:

```markdown
---
title: <card slug> — {{DATE}}
created: {{DATE}}
tags: [nightly-builds, report]
status: draft
---

# REPORT — <card title>

## Success criteria (from the card, verbatim)
<each criterion as a checkbox, checked only if proven below>

## Evidence
<for each criterion: the command you ran and its actual output, quoted>

## Deliverable
Branch `{{BRANCH}}`, commits: <git log --oneline of your commits>

## Deviations / notes
<anything you did differently than the card specified, and why; or "none">

## If this run failed
<where it stopped, what is on the branch, what the morning human should look at>
```

A cold reviewer who did not watch the run must be able to verify every claim
from the report alone. Quote real command output — never summarize a result you
did not actually observe.

## The verdict (mandatory — the launcher parses this)

After writing the report, the very LAST line of your final output must be
exactly one of:

```
NIGHTLY-VERDICT: success
NIGHTLY-VERDICT: failure
```

`success` only if you ran the card's done-condition and watched it pass.
Anything else — budget exhausted, blast-radius conflict, done-condition
unsatisfiable or failing — is `failure`, even if you stopped cleanly and the
branch is in good shape. An honest failure is a good outcome; a false success
poisons morning review.
