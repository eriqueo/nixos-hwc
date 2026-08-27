# dxlog

## Purpose
Ships `dxlog`, a CLI for querying DataX platform logs in DigitalOcean managed OpenSearch (trace/search/errors/loops/tail/live subcommands, markdown or JSON output). A Nix wrapper reads the OpenSearch credentials from agenix secrets at runtime and execs the vendored bash script. Enable via `hwc.home.apps.dxlog.enable`.

## Boundaries
- ✅ The `dxlog` wrapper (exports `DXLOG_OPENSEARCH_{HOST,USER,PASS}`, `DXLOG_DO_APP_ID` from `/run/agenix/opensearch-*`; port pinned to 25060) plus runtime deps curl and jq.
- ❌ Does not declare the opensearch-* secrets (`domains/secrets/declarations/`) and requires eric in the `secrets` group; does not run or manage OpenSearch itself. Does not install `doctl` — it enables `hwc.home.apps.doctl`, which owns that binary.

## Structure
- `index.nix` — enable option, secret-reading wrapper, package installs.
- `parts/dxlog.sh` — the actual query tool (v0.2.0), vendored bash.

## Changelog
- 2026-08-26: `pkgs.doctl` removed from `home.packages`; the module now sets `hwc.home.apps.doctl.enable = true` instead. `doctl auth init` had been failing with a 401, so `dxlog live` was broken; the new `apps/doctl` wrapper supplies the token from agenix. Installing both would collide on `bin/doctl`. Verified after the change: `dxlog live` connects and holds the tail open.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
