# nixos-hwc

NixOS flake managing HWC machines. The agent harness runs on hwc-laptop,
hwc-server, and hwc-work. Charter v12.6:
domains = capabilities, profiles = roles, machines = instances. Each
domain's `README.md` carries its structure and changelog.

Read `CHARTER.md`. Not "before architectural work" — that phrasing was the
bug (§0.12): it gates the rule on a judgement made before you know enough
to make it, and additive work never feels architectural. `nixos-primer.sh`
injects the charter and a live `ls domains/` map on your first edit here,
triggered by the file's path rather than your read of the task.

## Build & gate
- Commit BEFORE building. The tracked `.githooks/pre-commit` runs the nine
  charter-law checks (`core.hooksPath` points at a store dir that
  `hwc.home.core.repoHooks` generates at activation and that forwards to it);
  reproduce one with `nix build --no-link .#checks.x86_64-linux.charter-law<N>`.
  `nix flake check` runs them all — `--no-build` does NOT.
- Two activation lanes; run `hostname` first and state which lane applies:
  - HM-only (`domains/home/`, `profiles/*/home.nix`, `machines/*/home.nix`)
    → `hms` (fast, no sudo).
  - System or mixed → `sudo nixos-rebuild switch --flake .#hwc-<host>`.
  Don't alternate lanes casually — each keeps its own HM generation and
  will trip "existing file in the way" on files the other placed.
- A build without a switch changes nothing; never report "live" from a build.
- Deploy from `main` in this checkout: rebase the worktree branch onto
  `origin/main`, `git merge --ff-only <branch>` here, then switch. Services
  read files from this checkout at runtime (`paths.nixos`), so it must hold
  exactly what runs, and `--ff-only` is what stops a deploy from dropping
  commits that are already live. If a switch fails verification, fix forward or
  `git revert` on `main`. Never check out a bare commit here: the pinned
  `post-checkout` guard returns to the branch and fails the checkout.

## Rules no lint catches yet
- Secrets: `group = "secrets"; mode = "0440"`.
- Native services need `User = lib.mkForce "eric"`; container PGID is 100.
- Ports: check `domains/networking/routes.nix` before claiming one.
- Paths come from `config.hwc.paths.*` (`domains/paths/paths.nix`).
- Laya/classifier adaptation: follow
  `/home/eric/900_vaults/brain/_library/ai-ml/laya_reliability_playbook.md`.
  Keep memory separate from unseen accuracy, tune only on development data,
  freeze identity-disjoint holdout before scoring, compare a cheap baseline,
  promote each decision axis separately, and use shadow mode plus a safe fallback.

## Before adding a file
Adding a file to a directory that already has files? Read **every** file in
it first, then name the sibling you ruled out and why it couldn't hold this
(§0.13). "It's a separate concern, so it deserves its own file" is the exact
instinct that produced `options.nix` and took three months to kill.

## On commit
Update the touched domain's `README.md` (`## Structure` + `## Changelog`)
in the same commit — `charter-gate.sh` computes which READMEs are missing
from the staged set and names them. Feature work lives in
`~/.nixos-worktrees/<name>`; this checkout stays on `main`.
