# docs/design

## Purpose
Architectural design proposals for nixos-hwc — written *before* an implementation
card lands, so the decision (and the rejected alternatives) is reviewable in
git. Each proposal names the follow-up card that will implement it.

## Boundaries
- ✅ manages: design docs comparing options for a not-yet-implemented change,
  with a single `## Recommendation` and a named follow-up card.
- ❌ does not manage: implementation guides (those live next to the code they
  describe), runbooks (`docs/troubleshooting/`), historical reports
  (`docs/archive/reports/`), or charter laws (`CHARTER.md`).

## Structure
| File | Purpose |
|------|---------|
| `flake-local-input-sourcing.md` | Picks a durable shape for sourcing Eric's own apps (`todui`, `khalt`, `workbench`) as flake inputs across hwc-laptop ↔ hwc-server. |

## Changelog
- 2026-06-18 — Add `flake-local-input-sourcing.md`: ratifies `github:` inputs
  (Option D) for the three local apps and names follow-up card `06 — gate
  unconditional-import of app inputs on profile membership`. Created
  `docs/design/` and this README (Charter Law 12).
