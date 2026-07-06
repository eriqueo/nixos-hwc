# pave-query-builder

## Purpose
Thin translator around the external `pave-query-builder` flake input (trap-safe Pave/JobTread API query builder, its own repo at `~/600_apps/pave-query-builder`). Imports the app's upstream HM module, feeds it HWC values (jt-mcp schema path), and adds HWC-only wiring: a read-only GraphiQL web shell (`pave-web`) as an on-demand localhost user service plus wofi launcher entries for both the web shell and the Textual TUI.

## Boundaries
- ✅ Manages: `hwc.home.apps.pave-query-builder.enable`; `programs.pave-query-builder` wiring; `pave-web.service` (127.0.0.1:8787, grant key read from `/run/agenix/jobtread-grant-key` at start); `pave-explorer` and `pave-query-builder` desktop entries.
- ❌ Does not manage: the app itself (upstream repo/flake input), the JobTread grant key secret (`domains/secrets/`), or the mutation guardrail defaults (app built-in; widen here deliberately if ever needed).

## Structure
- `index.nix` — imports upstream HM module; options; pave-web start/open launcher scripts, user service, desktop entries.

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
