# docs/

Cross-domain documentation. Domain-specific docs belong in `domains/*/README.md`
(Charter Law 12). One living doc per topic; superseded material moves (not
copies) to `archive/`.

## Structure

```
docs/
├── AGENTS.md          # Agent/Claude project instructions (CLAUDE.md symlinks here)
├── INSTALL.md         # Machine bootstrap
├── QUICK-REFERENCE.md # Operator cheat sheet
├── TAXONOMY.md        # Naming taxonomy
├── FILESYSTEM_CHARTER.md  # ~/ home-directory organization charter
├── archive/           # Historical one-offs: completed plans, old reports, superseded
│                      #   guides, old charter versions (charter-versions/), AI dumps.
│                      #   Single-copy rule: nothing here may also exist outside archive/.
├── audits/            # Media/storage audit notes (their generated .sh manifests live
│                      #   in workspace/media/manifests/)
├── automation/        # n8n implementation guide
├── claude-agents/     # Agent creation guides/templates
├── infrastructure/    # Hardware reference: GPU, ports, devices, retention
├── media/             # Beets/music library guides
├── monitoring/        # Monitoring reference
├── patterns/          # Reusable cross-domain patterns (containers, paths, config-first)
├── plans/             # Active cross-domain plans/specs (repo-wide proposals live in
│                      #   workspace/plans/ per CHARTER §6)
├── policies/          # Data retention and similar policies
├── standards/         # HWC_STANDARDS, permission-patterns
├── templates/         # DOMAIN_README_TEMPLATE
└── troubleshooting/   # Debugging guides
```

## When to use docs/ vs domain READMEs

| Content Type | Location |
|-------------|----------|
| Domain purpose, boundaries, structure, changelog | `domains/*/README.md` |
| Cross-domain patterns | `docs/patterns/` |
| Active plans affecting multiple domains | `docs/plans/` |
| Repo/architecture proposals & audits | `workspace/plans/` |
| Hardware/device reference | `docs/infrastructure/` |
| Completed/superseded anything | `docs/archive/` (moved, never copied) |

## Rules

1. **Archive means move.** A file may exist in `archive/` or outside it, never both.
2. **Executable scripts are not documentation** — generated manifests and ops
   scripts go to `workspace/`.
3. **AI session output is ephemeral** — reports/plans from agent sessions are
   committed only by being merged into the one living doc for that topic.
4. One category, one folder — no singular/plural forks (`audit/` vs `audits/`).
5. Domain READMEs are the source of truth per domain; CHARTER.md is the
   architectural authority, not docs/.

## Changelog

- 2026-07-05: Audit cleanup (`workspace/plans/2026-07-05-systems-process-audit.md`).
  Deleted ~70 byte-identical archive duplicates; merged `audit/`→`audits/`;
  moved generated .sh manifests to `workspace/media/manifests/`; filed loose
  one-offs into `archive/`; rewrote this README and DOCUMENTATION_STANDARDS.md
  (was Charter v6.0-era) to match reality. docs/ shrank 7.4M → 1.7M.
