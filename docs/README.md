# docs/

Cross-domain documentation. Domain-specific docs belong in `domains/*/README.md` (per Charter Law 12).

## Structure

```
docs/
├── archive/          # Historical docs (completed projects, old reports, superseded guides)
├── infrastructure/   # Hardware reference (GPU, ports, device-specific)
├── media/            # Beets/music library guides
├── patterns/         # Reusable cross-domain patterns
├── plans/            # Active cross-domain plans
└── troubleshooting/  # Debugging guides
```

## When to Use docs/ vs Domain READMEs

| Content Type | Location |
|-------------|----------|
| Domain purpose, boundaries, structure | `domains/*/README.md` |
| Cross-domain patterns | `docs/patterns/` |
| Active plans affecting multiple domains | `docs/plans/` |
| Hardware/device reference | `docs/infrastructure/` |
| Completed projects, old reports | `docs/archive/` |

## Rules

- Domain READMEs are the source of truth for each domain (Charter Law 12)
- Archive docs older than 6 months after project completion
- Don't create docs that duplicate domain README content
- CHARTER.md is the architectural authority, not docs/

---

**Last Updated**: 2026-02-26
**Charter Version**: v10.4
