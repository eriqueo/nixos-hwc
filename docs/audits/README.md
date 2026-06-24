# `docs/audits/` — point-in-time audit reports

This directory holds **read-only point-in-time audits** of repo state, disk
state, or system state. Each audit is a frozen snapshot intended to inform a
follow-up gated change card; an audit document **never** describes a mutation
performed by the audit run itself.

## Structure

| Path                              | What it is                                                          |
| --------------------------------- | ------------------------------------------------------------------- |
| `mnt-hot/orphan-audit.md`         | `/mnt/hot` orphan / crust audit (2026-06-24). Cross-references on-disk subtrees against the active-paths set self-derived from `~/.nixos`, classifies each as active vs orphan, and proposes (a) media to consolidate into `/mnt/media` and (b) folders safe to delete. **Report only; nothing was changed.** |

## Conventions

- One subdirectory per audit subject (`mnt-hot/`, `mnt-media/`, `opt/`, etc.).
- Audit files are dated in their frontmatter or top-of-document line.
- Audits are **append-only history**: when a new audit replaces an old one, the
  old file is renamed `*-YYYY-MM-DD.md` rather than overwritten, so the diff
  trail survives.
- Any proposal inside an audit is **human-gated**. Execution lives in a
  separate card under the `mnt-hot-reconcile` (or equivalent) goal.

## Changelog

- 2026-06-24 — initial directory; added `mnt-hot/orphan-audit.md` from nightly
  card `02 — /mnt/hot orphan/crust audit`.
