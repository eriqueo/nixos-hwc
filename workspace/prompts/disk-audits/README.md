# Overnight Disk Audit Prompts

Self-contained Claude Code prompts that audit archive folders under
`/home/eric/200_personal/299_archive/` and produce a reviewable
relocation/delete plan **without taking destructive action**.

## How to use

Pick a prompt and run it in a fresh Claude Code session on `hwc-server`
(direct or via `/schedule` for an overnight remote agent). The agent
will write its report to `/home/eric/.nixos/workspace/plans/`. Review
the report, then run the proposed shell commands by hand.

## Safety rules baked into every prompt

- **No deletes, no moves, no writes outside the report file.** Every
  prompt instructs the agent to *propose* commands, never execute them.
- Reports go to `workspace/plans/disk-audit-<target>-<date>.md` so they
  show up in normal git status and can be reviewed before action.
- Every proposed command is shown as a shell block — pastable, not
  auto-executed.

## Prompts

| File | Target | Approx size |
|---|---|---|
| `audit-mac-dropbox.md` | `/home/eric/200_personal/299_archive/mac-dropbox/` | 26G |
| `audit-old-documents.md` | `/home/eric/200_personal/299_archive/old-documents/` | 2.4G |
| `audit-seagate.md` | `/home/eric/200_personal/299_archive/seagate-*` | 700M |

## Followup

After reviewing each report, the typical actions are:
- **Cold-archive** to `/mnt/backup/cold-archive/<category>/<date>/`
- **Delete** anything reproducible / junk / duplicates
- **Move to /mnt/hot/library/** if it's reference material that
  shouldn't be in Syncthing

Once a tree is fully relocated, remove its Syncthing folder definition
in `machines/{server,laptop}/config.nix` so it doesn't reappear.
